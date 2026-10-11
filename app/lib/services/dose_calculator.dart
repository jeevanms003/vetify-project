import '../models/drug.dart';
import '../models/calc_result.dart';

class DoseCalculatorResult {
  final DoseCalcResult? result;
  final String? errorMessage;

  const DoseCalculatorResult.success(this.result) : errorMessage = null;
  const DoseCalculatorResult.error(this.errorMessage) : result = null;

  bool get isSuccess => result != null;
}

class DoseCalculator {
  static const double lbToKgFactor = 0.45359237;

  /// Parses and validates user input for weight.
  /// Handles decimal commas (e.g. "4,5" -> 4.5), spaces, and unit conversion.
  /// Returns weight in kg, or throws an ArgumentError if impossible or invalid.
  static double parseWeight(String rawInput, String unit, {String species = 'dog'}) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Please enter a body weight.');
    }

    // Replace comma decimal separator with dot
    final normalized = trimmed.replaceAll(',', '.');

    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      throw ArgumentError('Invalid weight format: "$rawInput". Please enter a valid number.');
    }

    if (parsed <= 0) {
      throw ArgumentError('Weight must be strictly greater than 0.');
    }

    double weightKg = unit.toLowerCase() == 'lb' ? parsed * lbToKgFactor : parsed;

    // Biological sanity checks
    final canonicalSpecies = Drug.normalizeSpeciesKey(species);
    if (canonicalSpecies == 'cat') {
      if (weightKg < 0.05) {
        throw ArgumentError('Impossible feline weight: ${weightKg.toStringAsFixed(2)} kg is too small (minimum 0.05 kg / 0.11 lb).');
      }
      if (weightKg > 25.0) {
        throw ArgumentError('Impossible feline weight: ${weightKg.toStringAsFixed(1)} kg exceeds maximum feline limits (maximum 25 kg / 55 lb).');
      }
    } else if (canonicalSpecies == 'dog') {
      if (weightKg < 0.1) {
        throw ArgumentError('Impossible canine weight: ${weightKg.toStringAsFixed(2)} kg is too small (minimum 0.1 kg / 0.22 lb).');
      }
      if (weightKg > 140.0) {
        throw ArgumentError('Impossible canine weight: ${weightKg.toStringAsFixed(1)} kg exceeds realistic canine limits (maximum 140 kg / 308 lb).');
      }
    } else {
      if (weightKg < 0.01 || weightKg > 1500.0) {
        throw ArgumentError('Entered weight ${weightKg.toStringAsFixed(2)} kg is outside safe clinical bounds.');
      }
    }

    return weightKg;
  }

  /// Calculates the dose range in mg and volume range in mL for a drug and species.
  /// Refuses calculation if drug data is missing, inconsistent, or unusable.
  static DoseCalculatorResult calculateDose({
    required Drug drug,
    required String species,
    required String rawWeight,
    required String weightUnit,
    required String datasetVersion,
  }) {
    // 1. Check drug usability
    final unusableReason = drug.checkUnusableReason(species);
    if (unusableReason != null) {
      return DoseCalculatorResult.error(unusableReason);
    }

    // 2. Parse and validate weight
    double weightKg;
    try {
      weightKg = parseWeight(rawWeight, weightUnit, species: species);
    } catch (e) {
      return DoseCalculatorResult.error(e is ArgumentError ? e.message : e.toString());
    }

    // 3. Extract dose range
    final canonicalSpecies = Drug.normalizeSpeciesKey(species);
    final doseRange = drug.doses[canonicalSpecies];
    if (doseRange == null) {
      return DoseCalculatorResult.error('No dosage defined for $species.');
    }

    // 4. Compute dose in mg
    double minMg;
    double maxMg;
    final unitLower = doseRange.unit.toLowerCase().trim();

    if (unitLower == 'mg/kg') {
      minMg = weightKg * doseRange.min;
      maxMg = weightKg * doseRange.max;
    } else if (unitLower == 'mcg/kg' || unitLower == 'ug/kg') {
      // 1 mcg = 0.001 mg
      minMg = (weightKg * doseRange.min) / 1000.0;
      maxMg = (weightKg * doseRange.max) / 1000.0;
    } else {
      return DoseCalculatorResult.error('Unrecognized dose unit: "${doseRange.unit}". Cannot calculate safely.');
    }

    // 5. Check max total mg ceiling cap
    bool isCapped = false;
    if (drug.maxTotalMg != null && drug.maxTotalMg! > 0) {
      final cap = drug.maxTotalMg!;
      if (minMg > cap) {
        minMg = cap;
        isCapped = true;
      }
      if (maxMg > cap) {
        maxMg = cap;
        isCapped = true;
      }
    }

    // 6. Compute volume in mL
    final concMgPerMl = drug.parsedMgPerMl;
    if (concMgPerMl == null || concMgPerMl <= 0) {
      return DoseCalculatorResult.error('Unusable drug concentration: "${drug.concentrationRaw}".');
    }

    final volumeMin = minMg / concMgPerMl;
    final volumeMax = maxMg / concMgPerMl;

    // 7. Clinical alert checks
    String? clinicalAlert;
    if (volumeMin < 0.1 || volumeMax < 0.1) {
      clinicalAlert = 'Small volume alert (< 0.1 mL). Use a 1 mL tuberculin or insulin syringe. Refuse rounding to 1 decimal place to prevent fatal overdose.';
    } else if (volumeMax > 50.0 && drug.route.toUpperCase() != 'SC' && drug.route.toUpperCase() != 'IV CRI') {
      clinicalAlert = 'Large injection volume (> 50 mL). Verify dose or consider multiple injection sites.';
    }

    return DoseCalculatorResult.success(
      DoseCalcResult(
        drugId: drug.id,
        drugName: drug.name,
        datasetVersion: datasetVersion,
        species: canonicalSpecies,
        weightKg: weightKg,
        rawWeightEntered: rawWeight,
        weightUnit: weightUnit,
        doseMgMin: minMg,
        doseMgMax: maxMg,
        volumeMlMin: volumeMin,
        volumeMlMax: volumeMax,
        concentrationMgPerMl: concMgPerMl,
        concentrationDisplay: drug.concentrationRaw,
        isCappedByMaxTotal: isCapped,
        maxTotalMg: drug.maxTotalMg,
        clinicalAlert: clinicalAlert,
      ),
    );
  }
}
