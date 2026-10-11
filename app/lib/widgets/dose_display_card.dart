import 'package:flutter/material.dart';
import '../models/calc_result.dart';

class DoseDisplayCard extends StatelessWidget {
  final DoseCalcResult result;

  const DoseDisplayCard({super.key, required this.result});

  String _formatVolume(double val) {
    if (val < 0.1) {
      // Small doses: show 3 decimals if needed to avoid misleading zero
      return val.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    } else if (val < 1.0) {
      return val.toStringAsFixed(2);
    } else {
      return val.toStringAsFixed(2);
    }
  }

  String _formatMg(double val) {
    if (val < 1.0) {
      return val.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return val.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSingleDose = (result.volumeMlMin - result.volumeMlMax).abs() < 0.0001;

    final volumeText = isSingleDose
        ? '${_formatVolume(result.volumeMlMin)} mL'
        : '${_formatVolume(result.volumeMlMin)} – ${_formatVolume(result.volumeMlMax)} mL';

    final mgText = isSingleDose
        ? '${_formatMg(result.doseMgMin)} mg'
        : '${_formatMg(result.doseMgMin)} – ${_formatMg(result.doseMgMax)} mg';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Deep high-contrast slate
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8), width: 2), // Cyan border
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Bar with Dataset Version Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      result.drugName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                // Version badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Dataset: ${result.datasetVersion}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main High-Visibility Volume Hero Readout
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'CALCULATED VOLUME TO DRAW UP',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Huge volume display to make misreading impossible
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      volumeText,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 16),

                // Dose in mg and Stock Concentration alongside it
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Dose in mg
                    Column(
                      children: [
                        const Text(
                          'TOTAL DOSE (MG)',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mgText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(height: 32, width: 1, color: const Color(0xFF334155)),
                    // Concentration
                    Column(
                      children: [
                        const Text(
                          'STOCK CONCENTRATION',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.concentrationDisplay,
                          style: const TextStyle(
                            color: Color(0xFFFBBF24), // Amber
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                if (result.isCappedByMaxTotal) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB45309).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: Color(0xFFF59E0B), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ceiling Cap Enforced: Capped at maximum ${result.maxTotalMg} mg total dose.',
                            style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (result.clinicalAlert != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF43F5E)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFB7185), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.clinicalAlert!,
                            style: const TextStyle(color: Color(0xFFFECDD3), fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
