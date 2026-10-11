import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../models/calc_result.dart';
import '../services/cri_calculator.dart';
import '../services/dataset_repository.dart';
import '../services/audit_logger.dart';

class CriScreen extends StatefulWidget {
  final DatasetRepository repository;
  final AuditLogger auditLogger;

  const CriScreen({
    super.key,
    required this.repository,
    required this.auditLogger,
  });

  @override
  State<CriScreen> createState() => _CriScreenState();
}

class _CriScreenState extends State<CriScreen> {
  Drug? _selectedDrug;
  String _species = 'dog';
  String _weightUnit = 'kg';

  final TextEditingController _weightController = TextEditingController(text: '15');
  final TextEditingController _doseRateController = TextEditingController(text: '7.5');
  final TextEditingController _fluidRateController = TextEditingController(text: '50');
  final TextEditingController _bagSizeController = TextEditingController(text: '500');

  CriCalcResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _findDefaultCriDrug();
  }

  void _findDefaultCriDrug() {
    // Look for Dopraxine or any drug with CRI protocol
    final criDrugs = widget.repository.activeDrugs.where((d) => d.cri != null && d.cri!.isNotEmpty).toList();
    if (criDrugs.isNotEmpty) {
      _selectedDrug = criDrugs.first;
    } else if (widget.repository.activeDrugs.isNotEmpty) {
      _selectedDrug = widget.repository.activeDrugs.first;
    }
  }

  void _calculateCri() {
    setState(() {
      _errorMessage = null;
      _result = null;
    });

    if (_selectedDrug == null) {
      setState(() => _errorMessage = 'Please select a drug.');
      return;
    }

    final doseRate = double.tryParse(_doseRateController.text.replaceAll(',', '.'));
    final fluidRate = double.tryParse(_fluidRateController.text.replaceAll(',', '.'));
    final bagSize = double.tryParse(_bagSizeController.text.replaceAll(',', '.'));

    if (doseRate == null || fluidRate == null || bagSize == null) {
      setState(() => _errorMessage = 'Please enter valid numbers for dose rate, fluid rate, and bag size.');
      return;
    }

    final outcome = CriCalculator.calculateCri(
      drug: _selectedDrug!,
      species: _species,
      rawWeight: _weightController.text,
      weightUnit: _weightUnit,
      doseRateMcgKgMin: doseRate,
      fluidRateMlHr: fluidRate,
      bagSizeMl: bagSize,
      datasetVersion: widget.repository.currentVersion,
    );

    if (outcome.isSuccess) {
      final res = outcome.result!;
      setState(() {
        _result = res;
      });

      widget.auditLogger.recordCalculation(
        calcType: 'cri',
        datasetVersion: widget.repository.currentVersion,
        drugId: res.drugId,
        species: res.species,
        weightKg: res.weightKg,
        inputs: {
          'raw_weight': _weightController.text,
          'weight_unit': _weightUnit,
          'dose_rate_mcg_kg_min': doseRate,
          'fluid_rate_ml_hr': fluidRate,
          'bag_size_ml': bagSize,
        },
        result: res.toJson(),
      );
    } else {
      setState(() {
        _errorMessage = outcome.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final drugs = widget.repository.activeDrugs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Constant Rate Infusion (CRI)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              backgroundColor: const Color(0xFF0369A1),
              label: Text(
                'Dataset: ${widget.repository.currentVersion}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Select Drug
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SELECT CRI DRUG', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Drug>(
                      value: _selectedDrug,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: drugs.map((d) {
                        final hasCri = d.cri != null && d.cri!.isNotEmpty;
                        return DropdownMenuItem<Drug>(
                          value: d,
                          child: Text(
                            '${d.name} (${d.concentrationRaw})${hasCri ? " [CRI INDICATED]" : ""}',
                            style: TextStyle(
                              color: hasCri ? const Color(0xFF38BDF8) : Colors.white,
                              fontWeight: hasCri ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedDrug = val;
                          _result = null;
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Parameters
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Weight
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Body Weight',
                              filled: true,
                              fillColor: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [ButtonSegment(value: 'kg', label: Text('kg')), ButtonSegment(value: 'lb', label: Text('lb'))],
                          selected: {_weightUnit},
                          onSelectionChanged: (set) => setState(() => _weightUnit = set.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Dose rate
                    TextField(
                      controller: _doseRateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Dose Rate (mcg/kg/min)',
                        hintText: 'e.g. 5 - 10 mcg/kg/min for Dopraxine',
                        filled: true,
                        fillColor: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Fluid rate
                    TextField(
                      controller: _fluidRateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fluid Rate (mL/hr)',
                        filled: true,
                        fillColor: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Bag size
                    TextField(
                      controller: _bagSizeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fluid Bag Size (mL)',
                        hintText: 'e.g. 250, 500, 1000 mL',
                        filled: true,
                        fillColor: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _calculateCri,
              icon: const Icon(Icons.water_drop_rounded),
              label: const Text('CALCULATE CRI INFUSION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488), // Teal
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF450A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDC2626)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 16),
              // CRI Results Card
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF14B8A6), width: 2),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_result!.drugName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        Chip(
                          backgroundColor: const Color(0xFF0F766E),
                          label: Text('Dataset: ${_result!.datasetVersion}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('VOLUME OF DRUG TO ADD TO BAG', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${_result!.drugVolumeMl.toStringAsFixed(2)} mL',
                      style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 40, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BAG DURATION', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            const SizedBox(height: 4),
                            Text(
                              '${_result!.durationHours.toStringAsFixed(1)} hours '
                              '(${(_result!.durationHours * 60).round()} min)',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('TOTAL DRUG IN BAG', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            const SizedBox(height: 4),
                            Text(
                              '${_result!.totalDrugMg.toStringAsFixed(2)} mg',
                              style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Bag Displacement Notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0284C7)),
                      ),
                      child: Text(
                        _result!.displacementNote,
                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
