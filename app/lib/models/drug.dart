import 'dart:math';

class DoseRange {
  final double min;
  final double max;
  final String unit; // 'mg/kg' or 'mcg/kg'

  const DoseRange({
    required this.min,
    required this.max,
    required this.unit,
  });

  factory DoseRange.fromJson(Map<String, dynamic> json) {
    final minVal = (json['min'] as num).toDouble();
    final maxVal = (json['max'] as num).toDouble();
    final unitVal = (json['unit'] as String? ?? 'mg/kg').trim();
    return DoseRange(
      min: minVal,
      max: maxVal,
      unit: unitVal,
    );
  }

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'unit': unit,
      };

  bool get isInverted => min > max;
  bool get hasPositiveDoses => min > 0 && max > 0;
}

class CriRange {
  final double min;
  final double max;
  final String unit; // 'mcg/kg/min' or 'mg/kg/hr'

  const CriRange({
    required this.min,
    required this.max,
    required this.unit,
  });

  factory CriRange.fromJson(Map<String, dynamic> json) {
    return CriRange(
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      unit: (json['unit'] as String? ?? 'mcg/kg/min').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'unit': unit,
      };

  bool get isInverted => min > max;
  bool get hasPositiveDoses => min > 0 && max > 0;
}

class Drug {
  final String id;
  final String name;
  final String concentrationRaw;
  final String route;
  final double? maxTotalMg;
  final Map<String, DoseRange?> doses; // Canonical species -> range (or null)
  final Map<String, CriRange?>? cri;
  final bool isWithdrawn;
  final String? withdrawalReason;

  Drug({
    required this.id,
    required this.name,
    required this.concentrationRaw,
    required this.route,
    this.maxTotalMg,
    required this.doses,
    this.cri,
    this.isWithdrawn = false,
    this.withdrawalReason,
  });

  static String normalizeSpeciesKey(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'dog' || lower == 'canine') return 'dog';
    if (lower == 'cat' || lower == 'feline') return 'cat';
    return lower;
  }

  factory Drug.fromJson(Map<String, dynamic> json, {bool isWithdrawn = false, String? withdrawalReason}) {
    final dosesMap = <String, DoseRange?>{};
    if (json['doses'] is Map) {
      final rawDoses = json['doses'] as Map<String, dynamic>;
      for (final entry in rawDoses.entries) {
        final canonicalKey = normalizeSpeciesKey(entry.key);
        if (entry.value == null) {
          dosesMap[canonicalKey] = null;
        } else if (entry.value is Map<String, dynamic>) {
          dosesMap[canonicalKey] = DoseRange.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }

    Map<String, CriRange?>? criMap;
    if (json['cri'] is Map) {
      criMap = <String, CriRange?>{};
      final rawCri = json['cri'] as Map<String, dynamic>;
      for (final entry in rawCri.entries) {
        final canonicalKey = normalizeSpeciesKey(entry.key);
        if (entry.value == null) {
          criMap[canonicalKey] = null;
        } else if (entry.value is Map<String, dynamic>) {
          criMap[canonicalKey] = CriRange.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }

    return Drug(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      concentrationRaw: (json['concentration'] as String? ?? '').trim(),
      route: (json['route'] as String? ?? '').trim(),
      maxTotalMg: json['max_total_mg'] != null ? (json['max_total_mg'] as num).toDouble() : null,
      doses: dosesMap,
      cri: criMap,
      isWithdrawn: isWithdrawn,
      withdrawalReason: withdrawalReason,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'concentration': concentrationRaw,
        'route': route,
        if (maxTotalMg != null) 'max_total_mg': maxTotalMg,
        'doses': doses.map((k, v) => MapEntry(k, v?.toJson())),
        if (cri != null) 'cri': cri!.map((k, v) => MapEntry(k, v?.toJson())),
      };

  /// Parses concentration in mg/mL.
  /// Handles "50 mg/mL", "1.5 mg/mL", "10%" (10% w/v = 100 mg/mL).
  /// Returns null if unusable or <= 0.
  double? get parsedMgPerMl {
    final s = concentrationRaw.trim();
    if (s.isEmpty) return null;

    // Check percentage: e.g. "10%" -> 100 mg/mL
    if (s.endsWith('%')) {
      final numStr = s.substring(0, s.length - 1).trim();
      final val = double.tryParse(numStr);
      if (val == null || val <= 0) return null;
      return val * 10.0;
    }

    // Check "X mg/mL" or "X mcg/mL"
    final parts = s.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    final numVal = double.tryParse(parts[0]);
    if (numVal == null || numVal <= 0) return null;

    if (parts.length > 1) {
      final unit = parts[1].toLowerCase();
      if (unit == 'mg/ml') return numVal;
      if (unit == 'mcg/ml' || unit == 'ug/ml') return numVal / 1000.0;
      if (unit == 'g/ml') return numVal * 1000.0;
    }
    return numVal;
  }

  /// Evaluates whether a drug's data for a given species is unusable,
  /// returning a clinical explanation if unusable, or null if usable.
  String? checkUnusableReason(String rawSpecies) {
    if (isWithdrawn) {
      return 'Drug withdrawn: ${withdrawalReason ?? "Clinically withdrawn from formulary"}';
    }

    final conc = parsedMgPerMl;
    if (conc == null || conc <= 0) {
      return 'Unusable concentration: "$concentrationRaw" (non-positive or unparseable)';
    }

    final species = normalizeSpeciesKey(rawSpecies);
    final hasDoseKey = doses.containsKey(species);
    final hasCriKey = cri?.containsKey(species) ?? false;

    if (!hasDoseKey && !hasCriKey) {
      return 'No dosage data defined for species: "$rawSpecies"';
    }

    final dose = doses[species];
    final criDose = cri?[species];

    if (dose == null && criDose == null) {
      return 'Dosage is not indicated or contraindicated for species: "$rawSpecies"';
    }

    if (dose != null) {
      if (dose.isInverted) {
        return 'Inconsistent dose range: min (${dose.min} ${dose.unit}) > max (${dose.max} ${dose.unit})';
      }
      if (!dose.hasPositiveDoses) {
        return 'Invalid non-positive dose values: min ${dose.min}, max ${dose.max}';
      }
    }

    if (criDose != null) {
      if (criDose.isInverted) {
        return 'Inconsistent CRI range: min (${criDose.min} ${criDose.unit}) > max (${criDose.max} ${criDose.unit})';
      }
      if (!criDose.hasPositiveDoses) {
        return 'Invalid non-positive CRI dose: min ${criDose.min}, max ${criDose.max}';
      }
    }

    return null;
  }

  bool isUsableForSpecies(String species) => checkUnusableReason(species) == null;
}
