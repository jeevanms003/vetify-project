import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/drug.dart';

class UpdateResult {
  final bool success;
  final String message;
  final String? oldVersion;
  final String? newVersion;

  const UpdateResult({
    required this.success,
    required this.message,
    this.oldVersion,
    this.newVersion,
  });
}

class DatasetRepository {
  // Configurable server base URL. Default localhost:8000 for local dev
  String serverBaseUrl;

  // The official Ed25519 public key hex for Vetifi dataset distribution
  final String publicKeyHex;

  String _currentVersion = 'v14';
  List<Drug> _activeDrugs = [];
  Map<String, String> _withdrawnReasons = {};

  DatasetRepository({
    this.serverBaseUrl = 'http://127.0.0.1:8000',
    this.publicKeyHex = '89b73f85942d07a3d3a1b3e4d156eed464e66ccd65fb8bc797615a93c3a584ea',
  });

  String get currentVersion => _currentVersion;
  List<Drug> get activeDrugs => List.unmodifiable(_activeDrugs);
  Map<String, String> get withdrawnReasons => Map.unmodifiable(_withdrawnReasons);

  /// Initializes repository. Loads active dataset from local sandbox file if present,
  /// otherwise falls back to bundled asset dataset_v14.json.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    serverBaseUrl = prefs.getString('server_url') ?? serverBaseUrl;

    File? activeFile;
    try {
      final dir = await getApplicationDocumentsDirectory();
      activeFile = File('${dir.path}/dataset_active.json');
    } catch (_) {
      // In unit test or non-platform environments, path_provider might fail
      activeFile = File('test_dataset_active.json');
    }

    if (activeFile.existsSync()) {
      try {
        final content = await activeFile.readAsString();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;
        _loadDatasetMap(jsonMap);
        return;
      } catch (e) {
        // Corrupted file, fall back to bundled asset
      }
    }

    // Load from assets
    await loadBaseFromAsset();
  }

  Future<void> loadBaseFromAsset() async {
    try {
      final jsonString = await rootBundle.loadString('assets/dataset_v14.json');
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      _loadDatasetMap(jsonMap);
    } catch (_) {
      // Fallback in test runner if asset bundle not initialized
      final testFile = File('../server/data/v14_base.json');
      if (testFile.existsSync()) {
        final jsonMap = jsonDecode(await testFile.readAsString()) as Map<String, dynamic>;
        _loadDatasetMap(jsonMap);
      }
    }
  }

  void _loadDatasetMap(Map<String, dynamic> jsonMap) {
    _currentVersion = jsonMap['dataset_version'] as String? ?? 'v14';

    final rawWithdrawn = jsonMap['withdrawn'] as List<dynamic>? ?? [];
    final withdrawnSet = rawWithdrawn.map((e) => e.toString()).toSet();

    final withdrawnInfo = jsonMap['withdrawn_info'] as Map<String, dynamic>? ?? {};
    _withdrawnReasons = withdrawnInfo.map((k, v) => MapEntry(k, v.toString()));

    final rawDrugs = jsonMap['drugs'] as List<dynamic>? ?? [];
    final list = <Drug>[];

    for (final item in rawDrugs) {
      if (item is Map<String, dynamic>) {
        final id = item['id'] as String? ?? '';
        final isWithdrawn = withdrawnSet.contains(id);
        final reason = _withdrawnReasons[id];
        list.add(Drug.fromJson(item, isWithdrawn: isWithdrawn, withdrawalReason: reason));
      }
    }

    _activeDrugs = list;
  }

  /// Verifies Ed25519 signature of payload bytes against the embedded public key
  Future<bool> verifySignature(List<int> payloadBytes, String signatureBase64) async {
    try {
      final algorithm = Ed25519();
      final pkBytes = <int>[];
      for (int i = 0; i < publicKeyHex.length; i += 2) {
        pkBytes.add(int.parse(publicKeyHex.substring(i, i + 2), radix: 16));
      }

      final pubKey = SimplePublicKey(pkBytes, type: KeyPairType.ed25519);
      final sigBytes = base64Decode(signatureBase64);
      final signature = Signature(sigBytes, publicKey: pubKey);

      return await algorithm.verify(payloadBytes, signature: signature);
    } catch (e) {
      return false;
    }
  }

  /// Verifies SHA256 checksum
  bool verifySha256(List<int> payloadBytes, String expectedHex) {
    final digest = crypto_pkg.sha256.convert(payloadBytes);
    return digest.toString().toLowerCase() == expectedHex.trim().toLowerCase();
  }

  /// Checks for manifest updates and applies them atomically if available
  Future<UpdateResult> checkForUpdates({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final manifestUri = Uri.parse('$serverBaseUrl/v1/manifest?schema=2&current=$_currentVersion');
      final manifestRes = await httpClient.get(manifestUri).timeout(const Duration(seconds: 8));

      if (manifestRes.statusCode == 304) {
        return UpdateResult(
          success: true,
          message: 'Dataset $_currentVersion is already up to date (304 Not Modified).',
          oldVersion: _currentVersion,
          newVersion: _currentVersion,
        );
      }

      if (manifestRes.statusCode != 200) {
        return UpdateResult(
          success: false,
          message: 'Server error fetching manifest: HTTP ${manifestRes.statusCode}',
        );
      }

      // Verify manifest signature if header present
      final manifestSig = manifestRes.headers['x-manifest-signature'];
      if (manifestSig != null) {
        final validSig = await verifySignature(manifestRes.bodyBytes, manifestSig);
        if (!validSig) {
          return const UpdateResult(
            success: false,
            message: 'SECURITY ALERT: Manifest signature verification failed! Update rejected.',
          );
        }
      }

      final manifestData = jsonDecode(manifestRes.body) as Map<String, dynamic>;
      final latestVersion = manifestData['latest_version'] as String;
      final expectedSha = manifestData['payload_sha256'] as String;
      final payloadSig = manifestData['payload_signature'] as String;
      final deltaAvailable = manifestData['delta_available'] as bool? ?? false;

      if (latestVersion == _currentVersion) {
        return UpdateResult(
          success: true,
          message: 'Current version $_currentVersion is the latest.',
          oldVersion: _currentVersion,
          newVersion: _currentVersion,
        );
      }

      // Download update payload
      final updateUri = deltaAvailable
          ? Uri.parse('$serverBaseUrl/v1/datasets/$latestVersion?from=$_currentVersion')
          : Uri.parse('$serverBaseUrl/v1/datasets/$latestVersion');

      final updateRes = await httpClient.get(updateUri).timeout(const Duration(seconds: 15));

      if (updateRes.statusCode != 200) {
        return UpdateResult(
          success: false,
          message: 'Failed to download update payload: HTTP ${updateRes.statusCode}',
        );
      }

      final payloadBytes = updateRes.bodyBytes;

      // 1. Verify SHA-256 Hash
      final shaHeader = updateRes.headers['x-payload-sha256'] ?? expectedSha;
      if (!verifySha256(payloadBytes, shaHeader)) {
        return const UpdateResult(
          success: false,
          message: 'SECURITY ALERT: SHA-256 checksum mismatch! Possible corrupted download.',
        );
      }

      // 2. Verify Ed25519 Cryptographic Signature
      final sigHeader = updateRes.headers['x-payload-signature'] ?? payloadSig;
      final isSignatureValid = await verifySignature(payloadBytes, sigHeader);
      if (!isSignatureValid) {
        return const UpdateResult(
          success: false,
          message: 'SECURITY ALERT: Ed25519 cryptographic signature invalid! Tampering detected.',
        );
      }

      // 3. Parse JSON safely
      Map<String, dynamic> updateJson;
      try {
        updateJson = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      } catch (e) {
        return UpdateResult(
          success: false,
          message: 'Malformed or truncated JSON payload received: $e',
        );
      }

      // Fetch withdrawal reasons if available
      try {
        final wRes = await httpClient.get(Uri.parse('$serverBaseUrl/v1/withdrawals')).timeout(const Duration(seconds: 3));
        if (wRes.statusCode == 200) {
          final wList = jsonDecode(wRes.body) as List<dynamic>;
          for (final item in wList) {
            if (item is Map<String, dynamic>) {
              _withdrawnReasons[item['drug_id'] as String] = item['reason'] as String;
            }
          }
        }
      } catch (_) {}

      // 4. Apply update atomically to local storage
      final applyResult = await applyUpdateAtomically(updateJson, latestVersion);
      return applyResult;
    } catch (e) {
      return UpdateResult(
        success: false,
        message: 'Network or update failure: $e',
      );
    }
  }

  /// Applies update payload atomically using atomic rename
  Future<UpdateResult> applyUpdateAtomically(Map<String, dynamic> updateJson, String targetVersion) async {
    final oldVer = _currentVersion;

    // Merge logic
    final currentDrugsMap = {for (final d in _activeDrugs) d.id: d.toJson()};

    if (updateJson.containsKey('drugs')) {
      // Full snapshot
      final fullDrugs = updateJson['drugs'] as List<dynamic>;
      currentDrugsMap.clear();
      for (final d in fullDrugs) {
        if (d is Map<String, dynamic>) {
          currentDrugsMap[d['id'] as String] = d;
        }
      }
    } else {
      // Delta update
      final withdrawn = updateJson['withdrawn'] as List<dynamic>? ?? [];
      for (final wId in withdrawn) {
        // Keep in map but mark withdrawn
        if (currentDrugsMap.containsKey(wId.toString())) {
          // Keep record with withdrawn flag
        }
      }

      final upserts = updateJson['upserts'] as List<dynamic>? ?? [];
      for (final up in upserts) {
        if (up is Map<String, dynamic>) {
          currentDrugsMap[up['id'] as String] = up;
        }
      }
    }

    final newDatasetObj = {
      'schema_version': 2,
      'dataset_version': targetVersion,
      'drugs': currentDrugsMap.values.toList(),
      'withdrawn': updateJson['withdrawn'] ?? [],
      'withdrawn_info': _withdrawnReasons,
    };

    final newContent = jsonEncode(newDatasetObj);

    // Atomically write to staging file then rename
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory('.');
    }

    final activeFile = File('${dir.path}/dataset_active.json');
    final stagingFile = File('${dir.path}/dataset_staging.tmp');

    // Write to staging file and flush to disk
    await stagingFile.writeAsString(newContent, flush: true);

    // Atomic replace
    await stagingFile.rename(activeFile.path);

    // Update in-memory state
    _loadDatasetMap(newDatasetObj);

    return UpdateResult(
      success: true,
      message: 'Successfully updated dataset from $oldVer to $targetVersion.',
      oldVersion: oldVer,
      newVersion: targetVersion,
    );
  }
}
