import 'dart:math';

class DoseCalcResult {
  final String drugId;
  final String drugName;
  final String datasetVersion;
  final String species;
  final double weightKg;
  final String rawWeightEntered;
  final String weightUnit;
  final double doseMgMin;
  final double doseMgMax;
  final double volumeMlMin;
  final double volumeMlMax;
  final double concentrationMgPerMl;
  final String concentrationDisplay;
  final bool isCappedByMaxTotal;
  final double? maxTotalMg;
  final String? clinicalAlert;

  const DoseCalcResult({
    required this.drugId,
    required this.drugName,
    required this.datasetVersion,
    required this.species,
    required this.weightKg,
    required this.rawWeightEntered,
    required this.weightUnit,
    required this.doseMgMin,
    required this.doseMgMax,
    required this.volumeMlMin,
    required this.volumeMlMax,
    required this.concentrationMgPerMl,
    required this.concentrationDisplay,
    required this.isCappedByMaxTotal,
    this.maxTotalMg,
    this.clinicalAlert,
  });

  Map<String, dynamic> toJson() => {
        'drug_id': drugId,
        'drug_name': drugName,
        'dataset_version': datasetVersion,
        'species': species,
        'weight_kg': weightKg,
        'dose_mg_min': doseMgMin,
        'dose_mg_max': doseMgMax,
        'volume_ml_min': volumeMlMin,
        'volume_ml_max': volumeMlMax,
        'concentration_mg_per_ml': concentrationMgPerMl,
        'concentration_display': concentrationDisplay,
        'is_capped_by_max_total': isCappedByMaxTotal,
        if (maxTotalMg != null) 'max_total_mg': maxTotalMg,
      };
}

class CriCalcResult {
  final String drugId;
  final String drugName;
  final String datasetVersion;
  final String species;
  final double weightKg;
  final double doseRateMcgKgMin;
  final double fluidRateMlHr;
  final double bagSizeMl;
  final double drugVolumeMl;
  final double durationHours;
  final double totalDrugMg;
  final double concentrationMgPerMl;
  final String displacementNote;

  const CriCalcResult({
    required this.drugId,
    required this.drugName,
    required this.datasetVersion,
    required this.species,
    required this.weightKg,
    required this.doseRateMcgKgMin,
    required this.fluidRateMlHr,
    required this.bagSizeMl,
    required this.drugVolumeMl,
    required this.durationHours,
    required this.totalDrugMg,
    required this.concentrationMgPerMl,
    required this.displacementNote,
  });

  Map<String, dynamic> toJson() => {
        'drug_id': drugId,
        'drug_name': drugName,
        'dataset_version': datasetVersion,
        'species': species,
        'weight_kg': weightKg,
        'dose_rate_mcg_kg_min': doseRateMcgKgMin,
        'fluid_rate_ml_hr': fluidRateMlHr,
        'bag_size_ml': bagSizeMl,
        'drug_volume_ml': drugVolumeMl,
        'duration_hours': durationHours,
        'total_drug_mg': totalDrugMg,
        'concentration_mg_per_ml': concentrationMgPerMl,
      };
}

class CalculationRecord {
  final String calcId;
  final DateTime timestamp;
  final String calcType; // 'dose' or 'cri'
  final String datasetVersion;
  final String drugId;
  final String species;
  final double weightKg;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> result;
  bool isSynced;

  CalculationRecord({
    required this.calcId,
    required this.timestamp,
    required this.calcType,
    required this.datasetVersion,
    required this.drugId,
    required this.species,
    required this.weightKg,
    required this.inputs,
    required this.result,
    this.isSynced = false,
  });

  factory CalculationRecord.fromJson(Map<String, dynamic> json) {
    return CalculationRecord(
      calcId: json['calc_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      calcType: json['calc_type'] as String? ?? 'dose',
      datasetVersion: json['dataset_version'] as String? ?? 'unknown',
      drugId: json['drug_id'] as String? ?? '',
      species: json['species'] as String? ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0.0,
      inputs: json['inputs'] as Map<String, dynamic>? ?? {},
      result: json['result'] as Map<String, dynamic>? ?? {},
      isSynced: json['is_synced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'calc_id': calcId,
        'timestamp': timestamp.toIso8601String(),
        'calc_type': calcType,
        'dataset_version': datasetVersion,
        'drug_id': drugId,
        'species': species,
        'weight_kg': weightKg,
        'inputs': inputs,
        'result': result,
        'is_synced': isSynced,
      };

  /// Format ready for server /v1/calc_logs POST
  Map<String, dynamic> toServerLog(String deviceId) => {
        'calc_id': calcId,
        'device_id': deviceId,
        'dataset_version': datasetVersion,
        'drug_id': drugId,
        'species': species,
        'weight_kg': weightKg,
        'inputs': inputs,
        'result': result,
        'created_at': timestamp.toIso8601String(),
      };
}
