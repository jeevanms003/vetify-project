import '../models/drug.dart';
import '../models/calc_result.dart';
import 'dose_calculator.dart';

class CriCalculatorResult {
  final CriCalcResult? result;
  final String? errorMessage;

  const CriCalculatorResult.success(this.result) : errorMessage = null;
  const CriCalculatorResult.error(this.errorMessage) : result = null;

  bool get isSuccess => result != null;
}

class CriCalculator {
  /// Calculates the Constant Rate Infusion (CRI) delivery parameters.
  ///
  /// Mathematical Derivation:
  /// 1. Patient drug rate (mg/hr) = (weightKg * doseRateMcgKgMin * 60 min/hr) / 1000 mcg/mg
  /// 2. Bag duration (hrs) = bagSizeMl / fluidRateMlHr
  /// 3. Total drug needed in bag (mg) = patientDrugRateMgHr * bagDurationHrs
  /// 4. Stock drug volume to add (mL) = totalDrugMg / stockConcentrationMgPerMl
  static CriCalculatorResult calculateCri({
    required Drug drug,
    required String species,
    required String rawWeight,
    required String weightUnit,
    required double doseRateMcgKgMin,
    required double fluidRateMlHr,
    required double bagSizeMl,
    required String datasetVersion,
  }) {
    final canonicalSpecies = Drug.normalizeSpeciesKey(species);

    // 1. Check drug usability for CRI
    if (drug.isWithdrawn) {
      return CriCalculatorResult.error(
        'Drug is withdrawn: ${drug.withdrawalReason ?? "Not permitted for clinical use"}',
      );
    }

    final concMgPerMl = drug.parsedMgPerMl;
    if (concMgPerMl == null || concMgPerMl <= 0) {
      return CriCalculatorResult.error('Unusable drug concentration: "${drug.concentrationRaw}".');
    }

    if (drug.cri == null || !drug.cri!.containsKey(canonicalSpecies)) {
      return CriCalculatorResult.error(
        'No CRI dosing protocol defined for drug "${drug.name}" in species "$species".',
      );
    }

    final criRange = drug.cri![canonicalSpecies];
    if (criRange == null) {
      return CriCalculatorResult.error(
        'CRI is contraindicated or not indicated for species "$species".',
      );
    }

    if (criRange.isInverted || !criRange.hasPositiveDoses) {
      return CriCalculatorResult.error(
        'Inconsistent CRI dosage protocol for drug "${drug.name}": min ${criRange.min} > max ${criRange.max}.',
      );
    }

    // 2. Validate input numbers
    double weightKg;
    try {
      weightKg = DoseCalculator.parseWeight(rawWeight, weightUnit, species: species);
    } catch (e) {
      return CriCalculatorResult.error(e is ArgumentError ? e.message : e.toString());
    }

    if (doseRateMcgKgMin <= 0) {
      return const CriCalculatorResult.error('Dose rate must be strictly greater than 0 mcg/kg/min.');
    }
    if (fluidRateMlHr <= 0) {
      return const CriCalculatorResult.error('Fluid rate must be strictly greater than 0 mL/hr.');
    }
    if (bagSizeMl <= 0) {
      return const CriCalculatorResult.error('Bag size must be strictly greater than 0 mL.');
    }

    // Check if dose rate is within recommended guidelines
    String? rateWarning;
    if (doseRateMcgKgMin < criRange.min || doseRateMcgKgMin > criRange.max) {
      rateWarning =
          'Notice: Entered rate ($doseRateMcgKgMin mcg/kg/min) is outside recommended range (${criRange.min} - ${criRange.max} ${criRange.unit}).';
    }

    // 3. Compute infusion calculations
    final drugRateMgPerHour = (weightKg * doseRateMcgKgMin * 60.0) / 1000.0;
    final durationHours = bagSizeMl / fluidRateMlHr;
    final totalDrugMg = drugRateMgPerHour * durationHours;
    final drugVolumeMl = totalDrugMg / concMgPerMl;

    // 4. Compute bag volume displacement effect
    final totalFluidVolume = bagSizeMl + drugVolumeMl;
    final dilutionPercent = (drugVolumeMl / totalFluidVolume) * 100.0;

    String displacementNote;
    if (dilutionPercent >= 2.0) {
      displacementNote =
          'Displacement Notice: Adding ${drugVolumeMl.toStringAsFixed(2)} mL will dilute bag by ${dilutionPercent.toStringAsFixed(1)}%. '
          'Withdraw ${drugVolumeMl.toStringAsFixed(2)} mL fluid from the bag BEFORE adding the drug to ensure accurate infusion concentration.';
    } else {
      displacementNote =
          'Displacement minimal (${dilutionPercent.toStringAsFixed(2)}% volume change). '
          'Clinically acceptable to inject ${drugVolumeMl.toStringAsFixed(2)} mL directly into bag.';
    }

    if (rateWarning != null) {
      displacementNote = '$rateWarning\n\n$displacementNote';
    }

    return CriCalculatorResult.success(
      CriCalcResult(
        drugId: drug.id,
        drugName: drug.name,
        datasetVersion: datasetVersion,
        species: canonicalSpecies,
        weightKg: weightKg,
        doseRateMcgKgMin: doseRateMcgKgMin,
        fluidRateMlHr: fluidRateMlHr,
        bagSizeMl: bagSizeMl,
        drugVolumeMl: drugVolumeMl,
        durationHours: durationHours,
        totalDrugMg: totalDrugMg,
        concentrationMgPerMl: concMgPerMl,
        displacementNote: displacementNote,
      ),
    );
  }
}
