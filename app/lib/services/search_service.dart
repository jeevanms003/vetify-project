import 'dart:async';
import 'dart:math';
import '../models/drug.dart';

class SearchMatch {
  final Drug drug;
  final int rank; // 0 = exact, 1 = prefix, 2 = substring, 3 = fuzzy
  final int score;

  const SearchMatch({
    required this.drug,
    required this.rank,
    required this.score,
  });
}

class SearchMetrics {
  int totalQueries = 0;
  double typicalLatencyMs = 0;
  double worstLatencyMs = 0;
  final List<double> recentLatencies = [];

  void recordLatency(double ms) {
    totalQueries++;
    recentLatencies.add(ms);
    if (recentLatencies.length > 50) recentLatencies.removeAt(0);

    worstLatencyMs = max(worstLatencyMs, ms);

    final sorted = List<double>.from(recentLatencies)..sort();
    typicalLatencyMs = sorted[sorted.length ~/ 2]; // median
  }
}

class SearchService {
  List<Drug> _allDrugs = [];
  int _latestSearchToken = 0;
  final SearchMetrics metrics = SearchMetrics();

  bool get isLoaded => _allDrugs.isNotEmpty;
  int get drugCount => _allDrugs.length;

  /// Loads base drugs and generates at least 50,000 synthetic clinical drugs
  void initializeWithBaseDrugs(List<Drug> baseDrugs) {
    final list = List<Drug>.from(baseDrugs);

    // Generate 50,000 realistic veterinary formulary entries
    const prefixes = [
      'Amoxi', 'Cefa', 'Doxy', 'Enro', 'Flu', 'Ket', 'Melox', 'Pred', 'Tram',
      'Atro', 'Bupre', 'Carpro', 'Clava', 'Dexa', 'Furo', 'Gaba', 'Hydr', 'Iver',
      'Marbo', 'Metron', 'Mirtaz', 'Oclaci', 'Ome', 'Peno', 'Pimo', 'Tera', 'Tolo',
      'Zola', 'Apo', 'Bena', 'Cipro', 'Dilti', 'Ena', 'Fenta', 'Imi', 'Lactu'
    ];
    const suffixes = [
      'cillin', 'mycin', 'profen', 'zole', 'flox', 'dine', 'pam', 'lol', 'xine',
      'pril', 'sone', 'tine', 'pril', 'cort', 'stat', 'vane', 'quin', 'mine',
      'trol', 'dil', 'rol', 'fen', 'mid', 'cin'
    ];

    final targetCount = 50000;
    int idCounter = 1000;

    for (int p = 0; p < prefixes.length && list.length < targetCount + baseDrugs.length; p++) {
      for (int s = 0; s < suffixes.length && list.length < targetCount + baseDrugs.length; s++) {
        for (int v = 1; v <= 60 && list.length < targetCount + baseDrugs.length; v++) {
          final name = '${prefixes[p]}${suffixes[s]}-$v';
          idCounter++;
          list.add(
            Drug(
              id: 'gen_$idCounter',
              name: name,
              concentrationRaw: '${(v % 50 + 1) * 2} mg/mL',
              route: v % 2 == 0 ? 'IV' : 'PO',
              doses: {
                'dog': DoseRange(min: 1.0 + (v % 5), max: 5.0 + (v % 5), unit: 'mg/kg'),
                'cat': DoseRange(min: 0.5 + (v % 2), max: 2.0 + (v % 2), unit: 'mg/kg'),
              },
            ),
          );
        }
      }
    }

    _allDrugs = list;
  }

  /// Levenshtein distance for fuzzy approximate matching
  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// Searches drugs with exact, prefix, substring, and approximate matches.
  /// Enforces race-condition immunity: results from slower, earlier queries are dropped.
  Future<List<Drug>?> search(String query, {int limit = 50}) async {
    final searchToken = ++_latestSearchToken;
    final stopwatch = Stopwatch()..start();

    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return _allDrugs.take(limit).toList();
    }

    // Yield to the event loop so keyboard events render smoothly
    await Future.delayed(Duration.zero);

    // If a newer query was already initiated, abandon immediately
    if (searchToken != _latestSearchToken) {
      return null;
    }

    final exactMatches = <SearchMatch>[];
    final prefixMatches = <SearchMatch>[];
    final substringMatches = <SearchMatch>[];
    final fuzzyMatches = <SearchMatch>[];

    final maxFuzzyDistance = cleanQuery.length <= 4 ? 1 : (cleanQuery.length <= 8 ? 2 : 3);

    for (final drug in _allDrugs) {
      // Periodic check for cooperative cancellation
      if (searchToken != _latestSearchToken) {
        return null; // A newer query has superseded this one!
      }

      final drugNameLower = drug.name.toLowerCase();

      // 1. Exact match
      if (drugNameLower == cleanQuery) {
        exactMatches.add(SearchMatch(drug: drug, rank: 0, score: 0));
        continue;
      }

      // 2. Prefix match
      if (drugNameLower.startsWith(cleanQuery)) {
        prefixMatches.add(
          SearchMatch(
            drug: drug,
            rank: 1,
            score: 100 + (drugNameLower.length - cleanQuery.length),
          ),
        );
        continue;
      }

      // 3. Substring match
      final idx = drugNameLower.indexOf(cleanQuery);
      if (idx != -1) {
        substringMatches.add(
          SearchMatch(
            drug: drug,
            rank: 2,
            score: 200 + idx,
          ),
        );
        continue;
      }

      // 4. Approximate / Fuzzy match (Levenshtein)
      // Check prefix first for speed, or entire name
      final dist = levenshtein(cleanQuery, drugNameLower);
      if (dist <= maxFuzzyDistance) {
        fuzzyMatches.add(
          SearchMatch(
            drug: drug,
            rank: 3,
            score: 300 + dist * 10 + (drugNameLower.length - cleanQuery.length).abs(),
          ),
        );
      }
    }

    // Final race-condition check before returning results
    if (searchToken != _latestSearchToken) {
      return null; // Discard! A faster, later query has already completed or is in progress.
    }

    // Sort within categories by score
    prefixMatches.sort((a, b) => a.score.compareTo(b.score));
    substringMatches.sort((a, b) => a.score.compareTo(b.score));
    fuzzyMatches.sort((a, b) => a.score.compareTo(b.score));

    final combined = <Drug>[
      ...exactMatches.map((m) => m.drug),
      ...prefixMatches.map((m) => m.drug),
      ...substringMatches.map((m) => m.drug),
      ...fuzzyMatches.map((m) => m.drug),
    ];

    stopwatch.stop();
    metrics.recordLatency(stopwatch.elapsedMicroseconds / 1000.0);

    return combined.take(limit).toList();
  }
}
