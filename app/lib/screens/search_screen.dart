import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../services/search_service.dart';

class SearchScreen extends StatefulWidget {
  final SearchService searchService;
  final Function(Drug)? onSelectDrug;

  const SearchScreen({
    super.key,
    required this.searchService,
    this.onSelectDrug,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  List<Drug> _searchResults = [];
  bool _isSearching = false;
  double? _lastLatencyMs;

  @override
  void initState() {
    super.initState();
    _performSearch('');
  }

  void _performSearch(String query) async {
    final sw = Stopwatch()..start();
    setState(() => _isSearching = true);

    final results = await widget.searchService.search(query);
    sw.stop();

    if (!mounted) return;

    // If results is null, it means a later query overtook this one (race condition prevented)
    if (results != null) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _lastLatencyMs = sw.elapsedMicroseconds / 1000.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.searchService.metrics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulary Search (50k+ Drugs)'),
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _queryController,
                  onChanged: _performSearch,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search drug name (e.g. melokin, benzaprl)...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                    suffixIcon: _queryController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              _queryController.clear();
                              _performSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),

                // Quick test pill chips for typos
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Try typos: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      _buildChip('melokin'),
                      _buildChip('benzaprl'),
                      _buildChip('velox'),
                      _buildChip('doprax'),
                      _buildChip('zentra'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Real-Time Latency & Index Telemetry Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTelemetryItem(
                  'INDEXED DRUGS',
                  '${widget.searchService.drugCount}',
                  const Color(0xFF38BDF8),
                ),
                _buildTelemetryItem(
                  'LAST QUERY',
                  _lastLatencyMs != null ? '${_lastLatencyMs!.toStringAsFixed(1)} ms' : '-',
                  const Color(0xFF10B981),
                ),
                _buildTelemetryItem(
                  'TYPICAL (MEDIAN)',
                  metrics.typicalLatencyMs > 0 ? '${metrics.typicalLatencyMs.toStringAsFixed(1)} ms' : '-',
                  const Color(0xFFFBBF24),
                ),
                _buildTelemetryItem(
                  'WORST CASE',
                  metrics.worstLatencyMs > 0 ? '${metrics.worstLatencyMs.toStringAsFixed(1)} ms' : '-',
                  const Color(0xFFF87171),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search Results List
          Expanded(
            child: _searchResults.isEmpty
                ? Center(
                    child: Text(
                      _isSearching ? 'Searching...' : 'No drugs matching query.',
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final drug = _searchResults[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: drug.isWithdrawn ? const Color(0xFFEF4444) : const Color(0xFF334155),
                          ),
                        ),
                        child: ListTile(
                          title: Row(
                            children: [
                              Text(
                                drug.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: drug.isWithdrawn ? const Color(0xFFEF4444) : Colors.white,
                                ),
                              ),
                              if (drug.isWithdrawn) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('WITHDRAWN', style: TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            'Conc: ${drug.concentrationRaw} • Route: ${drug.route} • ID: ${drug.id}',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                          onTap: () {
                            if (widget.onSelectDrug != null) {
                              widget.onSelectDrug!(drug);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8))),
        backgroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFF0284C7)),
        onPressed: () {
          _queryController.text = text;
          _performSearch(text);
        },
      ),
    );
  }

  Widget _buildTelemetryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
