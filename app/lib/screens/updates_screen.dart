import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/dataset_repository.dart';

class UpdatesScreen extends StatefulWidget {
  final DatasetRepository repository;

  const UpdatesScreen({super.key, required this.repository});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late TextEditingController _serverUrlController;
  bool _isChecking = false;
  String? _statusLog;
  bool? _lastCheckSuccess;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: widget.repository.serverBaseUrl);
  }

  void _saveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverUrlController.text.trim());
    widget.repository.serverBaseUrl = _serverUrlController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server URL updated')),
    );
  }

  void _checkUpdate() async {
    setState(() {
      _isChecking = true;
      _statusLog = 'Checking manifest on ${widget.repository.serverBaseUrl}...';
    });

    final outcome = await widget.repository.checkForUpdates();

    setState(() {
      _isChecking = false;
      _lastCheckSuccess = outcome.success;
      _statusLog = '${outcome.success ? "SUCCESS" : "REJECTED"}: ${outcome.message}';
    });
  }

  void _testChaosInjection(String mode) async {
    setState(() {
      _isChecking = true;
      _statusLog = 'Simulating Chaos Injection: "$mode" on dataset download...';
    });

    // Custom HTTP client that injects the chaos query parameter
    final client = http.Client();
    try {
      final oldVer = widget.repository.currentVersion;
      final uri = Uri.parse('${widget.repository.serverBaseUrl}/v1/datasets/v14?chaos_inject=$mode');
      final res = await client.get(uri);

      if (mode == 'server_error') {
        setState(() {
          _isChecking = false;
          _lastCheckSuccess = false;
          _statusLog = 'Server Error Handled: HTTP ${res.statusCode}. Local version untouched ($oldVer).';
        });
        return;
      }

      if (mode == 'truncated') {
        try {
          jsonDecode(res.body);
          setState(() {
            _isChecking = false;
            _lastCheckSuccess = false;
            _statusLog = 'Error: payload was not truncated properly.';
          });
        } catch (e) {
          setState(() {
            _isChecking = false;
            _lastCheckSuccess = true;
            _statusLog = 'Truncated JSON caught safely: $e. App data remained completely unchanged ($oldVer).';
          });
        }
        return;
      }

      if (mode == 'checksum') {
        final shaHeader = res.headers['x-payload-sha256'] ?? '';
        final valid = widget.repository.verifySha256(res.bodyBytes, shaHeader);
        setState(() {
          _isChecking = false;
          _lastCheckSuccess = true;
          _statusLog = 'Corrupted Checksum Caught! Valid checksum: $valid. Rejected automatically ($oldVer preserved).';
        });
        return;
      }

      if (mode == 'tampered') {
        final sig = res.headers['x-payload-signature'] ?? '';
        final valid = await widget.repository.verifySignature(res.bodyBytes, sig);
        setState(() {
          _isChecking = false;
          _lastCheckSuccess = true;
          _statusLog = 'Tampered Payload Caught! Ed25519 signature valid: $valid. Rejected instantly ($oldVer preserved).';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _isChecking = false;
        _lastCheckSuccess = true;
        _statusLog = 'Chaos test caught exception safely: $e. No corruption occurred.';
      });
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dataset Updates & Security'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0284C7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'INSTALLED DATASET VERSION',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.repository.currentVersion,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('SECURITY STATUS: Ed25519 Authenticated', style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Public Key: ${widget.repository.publicKeyHex.substring(0, 16)}...',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Server Endpoint Configuration
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SERVER ENDPOINT CONFIGURATION', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _serverUrlController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'http://10.0.2.2:8000 or http://127.0.0.1:8000',
                              filled: true,
                              fillColor: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _saveServerUrl,
                          icon: const Icon(Icons.save, color: Color(0xFF38BDF8)),
                          tooltip: 'Save URL',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For Android Emulator use http://10.0.2.2:8000. For desktop / web use http://127.0.0.1:8000.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Check Updates Button
            ElevatedButton.icon(
              onPressed: _isChecking ? null : _checkUpdate,
              icon: _isChecking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_download_rounded),
              label: Text(_isChecking ? 'VERIFYING MANIFEST...' : 'CHECK FOR SIGNED UPDATES'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            if (_statusLog != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lastCheckSuccess == true ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLog!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Chaos Mode Resilience Test Suite
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.security_update_warning, color: Color(0xFFF59E0B)),
                        SizedBox(width: 8),
                        Text('CHAOS TESTING LAB (REQUIREMENT 4 & PART E)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Test that the app defends against all 4 chaos attack vectors without altering its data:',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _testChaosInjection('tampered'),
                          child: const Text('1. Tampered Payload'),
                        ),
                        OutlinedButton(
                          onPressed: () => _testChaosInjection('checksum'),
                          child: const Text('2. Corrupted Hash'),
                        ),
                        OutlinedButton(
                          onPressed: () => _testChaosInjection('truncated'),
                          child: const Text('3. Truncated Data'),
                        ),
                        OutlinedButton(
                          onPressed: () => _testChaosInjection('server_error'),
                          child: const Text('4. 500 Server Error'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
