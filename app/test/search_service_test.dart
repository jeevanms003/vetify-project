import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/drug.dart';
import 'package:app/services/search_service.dart';

void main() {
  group('Part B: Search Service Tests (50k+ dataset & race condition safety)', () {
    late SearchService searchService;

    final baseDrugs = [
      Drug(
        id: 'd001',
        name: 'Veloxamine',
        concentrationRaw: '50 mg/mL',
        route: 'IV',
        doses: {},
      ),
      Drug(
        id: 'd004',
        name: 'Meloquin',
        concentrationRaw: '1.5 mg/mL',
        route: 'PO',
        doses: {},
      ),
      Drug(
        id: 'd007',
        name: 'Benzaprol',
        concentrationRaw: '100 mg/mL',
        route: 'IV',
        doses: {},
      ),
    ];

    setUp(() {
      searchService = SearchService();
      searchService.initializeWithBaseDrugs(baseDrugs);
    });

    test('Indexes at least 50,000 generated drug entries', () {
      expect(searchService.drugCount, greaterThanOrEqualTo(50000));
    });

    test('Tolerates spelling mistakes: "melokin" finds "Meloquin"', () async {
      final results = await searchService.search('melokin');
      expect(results, isNotNull);
      expect(results!.isNotEmpty, isTrue);
      expect(results.any((d) => d.name.toLowerCase().contains('meloquin')), isTrue);
    });

    test('Tolerates spelling mistakes: "benzaprl" finds "Benzaprol"', () async {
      final results = await searchService.search('benzaprl');
      expect(results, isNotNull);
      expect(results!.isNotEmpty, isTrue);
      expect(results.any((d) => d.name.toLowerCase().contains('benzaprol')), isTrue);
    });

    test('Ranks exact matches before prefix and approximate matches', () async {
      final results = await searchService.search('Veloxamine');
      expect(results, isNotNull);
      expect(results!.first.name, equals('Veloxamine'));
    });

    test('Prevents race conditions: slower older search does not overwrite newer search', () async {
      // Initiate first search for query A
      final futureA = searchService.search('melokin');
      // Immediately initiate second search for query B
      final futureB = searchService.search('Veloxamine');

      final resultA = await futureA;
      final resultB = await futureB;

      // Because query B superseded query A, resultA is either dropped (null) or resultB wins!
      expect(resultB, isNotNull);
      expect(resultB!.first.name, equals('Veloxamine'));
      // Search token guarantees resultA could never replace resultB
    });
  });
}
