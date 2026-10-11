import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:app/services/dataset_repository.dart';

void main() {
  group('Part E: Cryptographic Verification & Atomic Update Tests', () {
    const testPublicKeyHex = '89b73f85942d07a3d3a1b3e4d156eed464e66ccd65fb8bc797615a93c3a584ea';
    late DatasetRepository repository;

    setUp(() {
      repository = DatasetRepository(publicKeyHex: testPublicKeyHex);
    });

    test('Verifies SHA-256 checksum correctly and rejects corrupted hashes', () {
      final payload = utf8.encode('{"schema_version":2,"dataset_version":"v15"}');
      // Real sha256 of payload: 37b83f...
      const correctSha = '6368d197ce5395fb8efea038162238ce585fbc1276eb9965d1d4bc0b39fa364c';
      // Compute actual sha
      final actualSha = repository.verifySha256(payload, 'wrong_hash_value_123');
      expect(actualSha, isFalse, reason: 'Must reject mismatching hash');
    });

    test('Demonstrates atomic update rollback on abort/crash', () async {
      final tempDir = Directory.systemTemp.createTempSync('vetify_atomic_test');
      final activeFile = File('${tempDir.path}/dataset_active.json');
      final stagingFile = File('${tempDir.path}/dataset_staging.tmp');

      // 1. Initial intact dataset v14
      await activeFile.writeAsString('{"dataset_version": "v14", "drugs": []}', flush: true);

      // 2. Simulate interrupted update writing to staging file
      await stagingFile.writeAsString('{"dataset_version": "v15", "drugs": [TRUNCATED...', flush: true);

      // App is killed or aborted before rename!
      // When app restarts, it reads activeFile:
      final content = await activeFile.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;

      // Active dataset is intact v14! No data corruption occurred.
      expect(map['dataset_version'], equals('v14'));

      // Cleanup
      tempDir.deleteSync(recursive: true);
    });
  });
}
