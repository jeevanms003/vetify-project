import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../models/calc_result.dart';
import '../services/dose_calculator.dart';
import '../services/dataset_repository.dart';
import '../services/audit_logger.dart';
import '../widgets/dose_display_card.dart';

class DoseScreen extends StatefulWidget {
  final DatasetRepository repository;
  final AuditLogger auditLogger;

  const DoseScreen({
    super.key,
    required this.repository,
    required this.auditLogger,
  });

  @override
  State<DoseScreen> createState() => _DoseScreenState();
}

class _DoseScreenState extends State<DoseScreen> {
  Drug? _selectedDrug;
  String _selectedSpecies = 'dog';
  String _weightUnit = 'kg';
  final TextEditingController _weightController = TextEditingController();

  DoseCalcResult? _calculationResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.repository.activeDrugs.isNotEmpty) {
      _selectedDrug = widget.repository.activeDrugs.first;
    }
  }

  void _calculate() {
    setState(() {
      _errorMessage = null;
      _calculationResult = null;
    });

    if (_selectedDrug == null) {
      setState(() => _errorMessage = 'Please select a drug.');
      return;
    }

    final rawWeight = _weightController.text;
    final calcOutcome = DoseCalculator.calculateDose(
      drug: _selectedDrug!,
      species: _selectedSpecies,
      rawWeight: rawWeight,
      weightUnit: _weightUnit,
      datasetVersion: widget.repository.currentVersion,
    );

    if (calcOutcome.isSuccess) {
      final res = calcOutcome.result!;
      setState(() {
        _calculationResult = res;
      });

      // Save to audit logger locally (without blocking or making network calls)
      widget.auditLogger.recordCalculation(
        calcType: 'dose',
        datasetVersion: widget.repository.currentVersion,
        drugId: res.drugId,
        species: res.species,
        weightKg: res.weightKg,
        inputs: {
          'raw_weight': rawWeight,
          'weight_unit': _weightUnit,
          'species': _selectedSpecies,
        },
        result: res.toJson(),
      );
    } else {
      setState(() {
        _errorMessage = calcOutcome.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final drugs = widget.repository.activeDrugs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Dose Calculator'),
        actions: [
          // Dataset version pill
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
            // Drug Selection
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
                    const Text(
                      'SELECT DRUG',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
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
                        return DropdownMenuItem<Drug>(
                          value: d,
                          child: Text(
                            '${d.name} (${d.concentrationRaw}, ${d.route})${d.isWithdrawn ? " [WITHDRAWN]" : ""}',
                            style: TextStyle(
                              color: d.isWithdrawn ? const Color(0xFFEF4444) : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedDrug = val;
                          _calculationResult = null;
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Species & Weight Inputs
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
                    // Species Segmented Control
                    const Text(
                      'PATIENT SPECIES',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'dog', label: Text('Canine (Dog)'), icon: Icon(Icons.pets)),
                        ButtonSegment(value: 'cat', label: Text('Feline (Cat)'), icon: Icon(Icons.cruelty_free)),
                      ],
                      selected: {_selectedSpecies},
                      onSelectionChanged: (set) {
                        setState(() {
                          _selectedSpecies = set.first;
                          _calculationResult = null;
                          _errorMessage = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Body weight
                    const Text(
                      'BODY WEIGHT',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'e.g. 4.5 or 4,5',
                              hintStyle: const TextStyle(color: Color(0xFF64748B)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'kg', label: Text('kg')),
                            ButtonSegment(value: 'lb', label: Text('lb')),
                          ],
                          selected: {_weightUnit},
                          onSelectionChanged: (set) {
                            setState(() {
                              _weightUnit = set.first;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Calculate Button
            ElevatedButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('CALCULATE SAFE DOSE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            // Error / Refused Calculation Banner
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF450A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDC2626), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 24),
                        SizedBox(width: 8),
                        Text(
                          'CALCULATION REFUSED (SAFETY LOCK)',
                          style: TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],

            // Success Display Card
            if (_calculationResult != null) ...[
              DoseDisplayCard(result: _calculationResult!),
            ],
          ],
        ),
      ),
    );
  }
}
