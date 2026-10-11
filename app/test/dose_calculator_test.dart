import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/drug.dart';
import 'package:app/services/dose_calculator.dart';

void main() {
  group('Part A: DoseCalculator & Clinical Usability Tests', () {
    // 1. Weight Parsing & Comma handling
    test('Correctly parses weights with comma decimal separators and units', () {
      expect(DoseCalculator.parseWeight('4,5', 'kg', species: 'dog'), closeTo(4.5, 0.001));
      expect(DoseCalculator.parseWeight(' 10.25 ', 'kg', species: 'dog'), closeTo(10.25, 0.001));
      // 10 lb in kg: 10 * 0.45359237 = 4.5359237 kg
      expect(DoseCalculator.parseWeight('10', 'lb', species: 'dog'), closeTo(4.5359, 0.001));
      expect(DoseCalculator.parseWeight('10,0', 'lb', species: 'dog'), closeTo(4.5359, 0.001));
    });

    test('Rejects impossible weights', () {
      expect(() => DoseCalculator.parseWeight('-5', 'kg', species: 'dog'), throwsArgumentError);
      expect(() => DoseCalculator.parseWeight('0', 'kg', species: 'dog'), throwsArgumentError);
      expect(() => DoseCalculator.parseWeight('abc', 'kg', species: 'dog'), throwsArgumentError);
      // Dog over 140 kg
      expect(() => DoseCalculator.parseWeight('200', 'kg', species: 'dog'), throwsArgumentError);
      // Cat over 25 kg
      expect(() => DoseCalculator.parseWeight('30', 'kg', species: 'cat'), throwsArgumentError);
    });

    // 2. Standard Dose Calculation (Veloxamine: 50 mg/mL, Dog: 5-10 mg/kg, Cat: 2-4 mg/kg)
    test('Calculates accurate dose and volume ranges for Veloxamine', () {
      final veloxamine = Drug(
        id: 'd001',
        name: 'Veloxamine',
        concentrationRaw: '50 mg/mL',
        route: 'IV',
        doses: {
          'dog': const DoseRange(min: 5, max: 10, unit: 'mg/kg'),
          'cat': const DoseRange(min: 2, max: 4, unit: 'mg/kg'),
        },
      );

      // Dog weighing 10 kg:
      // Dose: 50 - 100 mg
      // Volume: 50/50 = 1.0 mL, 100/50 = 2.0 mL
      final resultDog = DoseCalculator.calculateDose(
        drug: veloxamine,
        species: 'dog',
        rawWeight: '10',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(resultDog.isSuccess, isTrue);
      expect(resultDog.result!.doseMgMin, equals(50.0));
      expect(resultDog.result!.doseMgMax, equals(100.0));
      expect(resultDog.result!.volumeMlMin, equals(1.0));
      expect(resultDog.result!.volumeMlMax, equals(2.0));

      // Cat weighing 2.5 kg:
      // Dose: 2.5 * 2 = 5 mg, 2.5 * 4 = 10 mg
      // Volume: 5/50 = 0.1 mL, 10/50 = 0.2 mL
      final resultCat = DoseCalculator.calculateDose(
        drug: veloxamine,
        species: 'cat',
        rawWeight: '2.5',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );
      expect(resultCat.isSuccess, isTrue);
      expect(resultCat.result!.volumeMlMin, closeTo(0.1, 0.001));
      expect(resultCat.result!.volumeMlMax, closeTo(0.2, 0.001));
    });

    // 3. Microgram Unit Handling (Tranzorel: 1 mg/mL, Dog: 10-20 mcg/kg)
    test('Converts mcg/kg to mg correctly without 1000x overdose', () {
      final tranzorel = Drug(
        id: 'd002',
        name: 'Tranzorel',
        concentrationRaw: '1 mg/mL',
        route: 'IM',
        doses: {
          'dog': const DoseRange(min: 10, max: 20, unit: 'mcg/kg'),
          'cat': const DoseRange(min: 5, max: 10, unit: 'mcg/kg'),
        },
      );

      // 20 kg Dog:
      // Dose: 20 * 10 mcg = 200 mcg = 0.2 mg
      // Dose Max: 20 * 20 mcg = 400 mcg = 0.4 mg
      // Volume: 0.2 mg / 1 mg/mL = 0.2 mL, 0.4 mL
      final result = DoseCalculator.calculateDose(
        drug: tranzorel,
        species: 'dog',
        rawWeight: '20',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(result.isSuccess, isTrue);
      expect(result.result!.doseMgMin, closeTo(0.2, 0.0001));
      expect(result.result!.doseMgMax, closeTo(0.4, 0.0001));
      expect(result.result!.volumeMlMin, closeTo(0.2, 0.0001));
      expect(result.result!.volumeMlMax, closeTo(0.4, 0.0001));
    });

    // 4. Ceiling Cap (Zentrafen: 100 mg/mL, max_total_mg: 400, Dog: 10-15 mg/kg)
    test('Enforces max_total_mg cap on heavy animals', () {
      final zentrafen = Drug(
        id: 'd008',
        name: 'Zentrafen',
        concentrationRaw: '100 mg/mL',
        route: 'PO',
        maxTotalMg: 400.0,
        doses: {
          'dog': const DoseRange(min: 10, max: 15, unit: 'mg/kg'),
        },
      );

      // 40 kg Dog:
      // Uncapped min: 40 * 10 = 400 mg (equals cap)
      // Uncapped max: 40 * 15 = 600 mg (exceeds cap -> must be capped at 400 mg!)
      final result = DoseCalculator.calculateDose(
        drug: zentrafen,
        species: 'dog',
        rawWeight: '40',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(result.isSuccess, isTrue);
      expect(result.result!.isCappedByMaxTotal, isTrue);
      expect(result.result!.doseMgMin, equals(400.0));
      expect(result.result!.doseMgMax, equals(400.0)); // Capped!
      expect(result.result!.volumeMlMax, equals(4.0)); // 400 mg / 100 mg/mL
    });

    // 5. Unusable Data Rejection
    test('Refuses calculation for Corvadil (inverted min > max)', () {
      final corvadil = Drug(
        id: 'd006',
        name: 'Corvadil',
        concentrationRaw: '10 mg/mL',
        route: 'IV',
        doses: {
          'dog': const DoseRange(min: 8, max: 4, unit: 'mg/kg'),
        },
      );

      final result = DoseCalculator.calculateDose(
        drug: corvadil,
        species: 'dog',
        rawWeight: '10',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Inconsistent dose range'));
    });

    test('Refuses calculation for Quilomid (zero concentration)', () {
      final quilomid = Drug(
        id: 'd009',
        name: 'Quilomid',
        concentrationRaw: '0 mg/mL',
        route: 'IV',
        doses: {
          'dog': const DoseRange(min: 1, max: 3, unit: 'mg/kg'),
        },
      );

      final result = DoseCalculator.calculateDose(
        drug: quilomid,
        species: 'dog',
        rawWeight: '10',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Unusable concentration'));
    });

    test('Refuses calculation for Pirovane in cats (cat: null)', () {
      final pirovane = Drug(
        id: 'd003',
        name: 'Pirovane',
        concentrationRaw: '25 mg/mL',
        route: 'PO',
        doses: {
          'dog': const DoseRange(min: 1, max: 2, unit: 'mg/kg'),
          'cat': null,
        },
      );

      final result = DoseCalculator.calculateDose(
        drug: pirovane,
        species: 'cat',
        rawWeight: '4',
        weightUnit: 'kg',
        datasetVersion: 'v14',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('not indicated or contraindicated'));
    });

    test('Refuses calculation for withdrawn drug', () {
      final withdrawnDrug = Drug(
        id: 'd009',
        name: 'Quilomid',
        concentrationRaw: '10 mg/mL',
        route: 'IV',
        isWithdrawn: true,
        withdrawalReason: 'Recalled by manufacturer',
        doses: {
          'dog': const DoseRange(min: 1, max: 2, unit: 'mg/kg'),
        },
      );

      final result = DoseCalculator.calculateDose(
        drug: withdrawnDrug,
        species: 'dog',
        rawWeight: '10',
        weightUnit: 'kg',
        datasetVersion: 'v15',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Recalled by manufacturer'));
    });
  });
}
