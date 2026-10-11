import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/drug.dart';
import 'package:app/services/cri_calculator.dart';

void main() {
  group('Part C: CRI Infusion Calculator Tests', () {
    final dopraxine = Drug(
      id: 'd011',
      name: 'Dopraxine',
      concentrationRaw: '40 mg/mL',
      route: 'IV CRI',
      doses: {},
      cri: {
        'dog': const CriRange(min: 5, max: 10, unit: 'mcg/kg/min'),
        'cat': null,
      },
    );

    test('Calculates exact CRI volume and duration for Dopraxine in dogs', () {
      // 20 kg Dog, dose rate 5 mcg/kg/min, fluid rate 50 mL/hr, bag size 500 mL
      // Drug rate: 20 * 5 * 60 / 1000 = 6 mg/hr
      // Bag duration: 500 / 50 = 10 hours
      // Total drug needed: 6 * 10 = 60 mg
      // Volume to add: 60 mg / 40 mg/mL = 1.5 mL
      final result = CriCalculator.calculateCri(
        drug: dopraxine,
        species: 'dog',
        rawWeight: '20',
        weightUnit: 'kg',
        doseRateMcgKgMin: 5.0,
        fluidRateMlHr: 50.0,
        bagSizeMl: 500.0,
        datasetVersion: 'v15',
      );

      expect(result.isSuccess, isTrue);
      final r = result.result!;
      expect(r.drugVolumeMl, closeTo(1.5, 0.001));
      expect(r.durationHours, closeTo(10.0, 0.001));
      expect(r.totalDrugMg, closeTo(60.0, 0.001));
      expect(r.displacementNote, contains('Displacement'));
    });

    test('Refuses Dopraxine CRI for cats because cat dose is null', () {
      final result = CriCalculator.calculateCri(
        drug: dopraxine,
        species: 'cat',
        rawWeight: '4',
        weightUnit: 'kg',
        doseRateMcgKgMin: 5.0,
        fluidRateMlHr: 20.0,
        bagSizeMl: 250.0,
        datasetVersion: 'v15',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('contraindicated or not indicated for species "cat"'));
    });

    test('Identifies significant bag volume displacement when drug volume >= 2%', () {
      // 40 kg Dog, 10 mcg/kg/min, 25 mL/hr, 100 mL bag
      // Drug rate: 40 * 10 * 60 / 1000 = 24 mg/hr
      // Duration: 100 / 25 = 4 hr
      // Total drug: 24 * 4 = 96 mg
      // Volume: 96 / 40 = 2.4 mL in a 100 mL bag (> 2.3% displacement!)
      final result = CriCalculator.calculateCri(
        drug: dopraxine,
        species: 'dog',
        rawWeight: '40',
        weightUnit: 'kg',
        doseRateMcgKgMin: 10.0,
        fluidRateMlHr: 25.0,
        bagSizeMl: 100.0,
        datasetVersion: 'v15',
      );

      expect(result.isSuccess, isTrue);
      expect(result.result!.drugVolumeMl, closeTo(2.4, 0.001));
      expect(result.result!.displacementNote, contains('Withdraw 2.40 mL fluid from the bag BEFORE adding'));
    });
  });
}
