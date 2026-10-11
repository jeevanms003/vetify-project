import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/calc_result.dart';

class AuditLogger {
  static const String _logFileName = 'calculation_audit_logs.json';
  final List<CalculationRecord> _records = [];
  final String deviceId;

  AuditLogger({String? deviceId})
      : deviceId = deviceId ?? 'device_${Random().nextInt(900000) + 100000}';

  List<CalculationRecord> get records => List.unmodifiable(_records);
  int get unsyncedCount => _records.where((r) => !r.isSynced).length;

  Future<void> initialize() async {
    try {
      File file;
      try {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$_logFileName');
      } catch (_) {
        file = File(_logFileName);
      }

      if (file.existsSync()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _records.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _records.add(CalculationRecord.fromJson(item));
          }
        }
      }
    } catch (_) {}
  }

  /// Records a calculation purely locally.
  /// NO NETWORK REQUEST IS MADE HERE to preserve offline guarantees.
  Future<CalculationRecord> recordCalculation({
    required String calcType,
    required String datasetVersion,
    required String drugId,
    required String species,
    required double weightKg,
    required Map<String, dynamic> inputs,
    required Map<String, dynamic> result,
  }) async {
    final calcId = 'calc_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    final rec = CalculationRecord(
      calcId: calcId,
      timestamp: DateTime.now(),
      calcType: calcType,
      datasetVersion: datasetVersion,
      drugId: drugId,
      species: species,
      weightKg: weightKg,
      inputs: inputs,
      result: result,
      isSynced: false,
    );

    _records.insert(0, rec);
    await _persistLogs();
    return rec;
  }

  Future<void> _persistLogs() async {
    try {
      File file;
      try {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$_logFileName');
      } catch (_) {
        file = File(_logFileName);
      }
      final jsonList = _records.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  /// Syncs unsynced calculations to the server when connection is available.
  Future<int> syncLogsToServer(String serverBaseUrl, {http.Client? client}) async {
    final unsynced = _records.where((r) => !r.isSynced).toList();
    if (unsynced.isEmpty) return 0;

    final httpClient = client ?? http.Client();
    final payload = unsynced.map((r) => r.toServerLog(deviceId)).toList();

    try {
      final res = await httpClient
          .post(
            Uri.parse('$serverBaseUrl/v1/calc_logs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        for (final rec in unsynced) {
          rec.isSynced = true;
        }
        await _persistLogs();
        return unsynced.length;
      }
    } catch (_) {}

    return 0;
  }
}
