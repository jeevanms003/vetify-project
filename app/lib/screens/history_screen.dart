import 'package:flutter/material.dart';
import '../services/audit_logger.dart';
import '../services/dataset_repository.dart';

class HistoryScreen extends StatefulWidget {
  final AuditLogger auditLogger;
  final DatasetRepository repository;

  const HistoryScreen({
    super.key,
    required this.auditLogger,
    required this.repository,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isSyncing = false;
  String? _syncStatus;

  void _syncLogs() async {
    setState(() {
      _isSyncing = true;
      _syncStatus = 'Uploading calculation records to /v1/calc_logs...';
    });

    final syncedCount = await widget.auditLogger.syncLogsToServer(widget.repository.serverBaseUrl);

    setState(() {
      _isSyncing = false;
      _syncStatus = syncedCount > 0
          ? 'Successfully synced $syncedCount record(s) to server.'
          : (widget.auditLogger.unsyncedCount == 0 ? 'All logs are already up to date.' : 'Upload failed. Server may be offline.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.auditLogger.records;
    final unsynced = widget.auditLogger.unsyncedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculation Audit History'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
            tooltip: 'Sync Logs to Server',
            onPressed: _isSyncing ? null : _syncLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Telemetry banner
          Container(
            padding: const EdgeInsets.all(14),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL STORED: ${records.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      'PENDING SYNC: $unsynced',
                      style: TextStyle(
                        color: unsynced > 0 ? const Color(0xFFFBBF24) : const Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _isSyncing || unsynced == 0 ? null : _syncLogs,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('SYNC LOGS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          if (_syncStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1E293B),
              child: Text(_syncStatus!, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
            ),

          Expanded(
            child: records.isEmpty
                ? const Center(
                    child: Text(
                      'No calculations performed yet.\nPerform a dose calculation to see audit logs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final r = records[index];
                      final isDose = r.calcType == 'dose';
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${r.species.toUpperCase()} (${r.weightKg.toStringAsFixed(1)} kg) - ${r.drugId}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: r.isSynced ? const Color(0xFF065F46) : const Color(0xFF78350F),
                                label: Text(
                                  r.isSynced ? 'SYNCED' : 'OFFLINE QUEUED',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Dataset: ${r.datasetVersion} • Mode: ${r.calcType.toUpperCase()} • Time: ${r.timestamp.toLocal().toString().substring(0, 19)}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Result: ${r.result['volume_ml_min'] ?? r.result['drug_volume_ml']} mL',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
