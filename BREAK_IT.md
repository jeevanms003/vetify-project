# BREAK_IT.md

## Vulnerability & Safety Failure Mode Analysis

In clinical veterinary practice, software errors translate directly into animal harm or mortality. Below is a rigorous analysis of the failure modes where a dose calculator could show an incorrect, misleading, or lethal number, how Vetifi defends against them, and the tests verifying each defense.

---

### Failure Modes, Protections, and Test Coverage

| # | Vulnerability / Failure Mode | Clinical Harm | Protection Implemented | Test Covering It |
|---|---|---|---|---|
| 1 | **Unit Confusion: $\mu\text{g}$ vs $\text{mg}$** (e.g. Tranzorel: 10–20 mcg/kg vs 1 mg/mL) | 1,000-fold fatal overdose | Strict unit parsing in `DoseCalculator`. All microgram inputs are normalized ($\div 1000$) to milligrams prior to volume calculation. | `app/test/dose_calculator_test.dart`: *"Converts mcg/kg to mg correctly without 1000x overdose"* |
| 2 | **Inverted Dose Range** (e.g. Corvadil: min 8, max 4 mg/kg) | Unpredictable under/overdosing; clinician confusion | Structural dataset validator checks $\text{min} \le \text{max}$. App refuses calculation and displays safety lock. | `app/test/dose_calculator_test.dart`: *"Refuses calculation for Corvadil (inverted min > max)"* |
| 3 | **Division by Zero: 0 mg/mL Concentration** (e.g. Quilomid) | Crash (`FormatException`) or `Infinity` resulting in massive syringe draw | Concentration validator rejects non-positive concentrations ($\le 0$). Refuses calculation. | `app/test/dose_calculator_test.dart`: *"Refuses calculation for Quilomid (zero concentration)"* |
| 4 | **Cross-Species Extrapolation** (e.g. Pirovane cat dose null) | Fatal feline toxicity (e.g. acetaminophen/NSAID liver failure) | Species isolation. Canonical keys (`dog`, `cat`). Missing or `null` species doses strictly block calculation. | `app/test/dose_calculator_test.dart`: *"Refuses calculation for Pirovane in cats (cat: null)"* |
| 5 | **Missing Ceiling Cap** (e.g. Zentrafen: max 400 mg on 40 kg dog) | Lethal toxic accumulation in giant canine breeds | `max_total_mg` cap evaluation. If $\text{weight} \times \text{dose} > \text{cap}$, total dose is clamped and a ceiling badge is displayed. | `app/test/dose_calculator_test.dart`: *"Enforces max_total_mg cap on heavy animals"* |
| 6 | **Premature Rounding on Neonates** (e.g. 2.5 kg kitten requiring 0.07 mL) | 0.07 mL rounded to 0.1 mL is a 43% overdose; 0.04 mL rounded to 0.0 mL is zero dose | Non-destructive precision. Volumes $< 0.1\text{ mL}$ preserved to 3 decimal places with small volume syringe alert. | `app/test/dose_calculator_test.dart`: *"Small volume alert (< 0.1 mL)"* |
| 7 | **CRI Fluid Bag Dilution** (Adding large drug volumes to fluid bags) | Significant underdosing (up to 20% dilution) | Dynamic dilution formula: $\frac{V_{\text{drug}}}{V_{\text{bag}} + V_{\text{drug}}}$. If $\ge 2\%$, app mandates withdrawing fluid before injection. | `app/test/cri_calculator_test.dart`: *"Identifies significant bag volume displacement when drug volume >= 2%"* |
| 8 | **Asynchronous Search Race Conditions** | Slower keystroke result replaces newer typed query, showing wrong drug | Monotonic sequence token counter in `SearchService`. Older asynchronous query completions are dropped. | `app/test/search_service_test.dart`: *"Prevents race conditions: slower older search does not overwrite newer search"* |
| 9 | **Poisoned / Tampered Dataset Updates** | Network attacker alters dosage or concentration | Ed25519 cryptographic signature verification and SHA-256 hash checks. Corrupted updates rejected. | `app/test/crypto_and_atomic_update_test.dart` & `server/tests/test_server.py` (Chaos simulation) |
| 10 | **Mid-Update Crash / Kill Corruption** | Partial dataset wipeout leaving database empty during emergency | Staging file write + atomic OS rename (`renameSync`). Zero in-place truncation. | `app/test/crypto_and_atomic_update_test.dart`: *"Demonstrates atomic update rollback on abort/crash"* |

---

### Unfixed Edge Case: Commercial Fluid Bag Manufacturer Overfill

#### The Issue:
Commercial intravenous fluid bags (e.g., 250 mL, 500 mL, and 1000 mL normal saline or LRS bags manufactured by Baxter, B. Braun, or Hospira) are legally packaged with a **5% to 12% factory overfill** to compensate for line priming and evaporation. A bag labeled "500 mL" almost always contains **525 mL to 555 mL** of actual fluid.

When our CRI calculator instructs the vet to add 1.5 mL of Dopraxine to a 500 mL bag, assuming the bag contains exactly 500.0 mL, the true concentration of the infusion will be approximately:
$$\frac{60\text{ mg}}{535\text{ mL}} = 0.112\text{ mg/mL} \quad (\text{instead of } 0.120\text{ mg/mL})$$
This results in a persistent **6% to 10% systematic underdosing** throughout the entire infusion run.

#### Why We Did Not Fix This:
To "fix" this mathematically, the veterinarian would have to aspirate and measure the exact volume of the commercial fluid bag before compounding. In veterinary clinical reality, emptying an entire IV bag into a graduated cylinder breaks the sterile closed system, creating an unacceptable risk of environmental bacterial contamination, endotoxin introduction, and fatal sepsis. 

In clinical pharmacology, manufacturer overfill is standard operating tolerance across both veterinary and human ICU protocols. Attempting to compensate with a synthetic fixed multiplier (e.g. assuming every 500 mL bag is 535 mL) would introduce equal inaccuracy across different manufacturers.

#### Would We Release the App Anyway?
**YES, absolutely.** 

Releasing the app is clinically sound because:
1. The 6–10% variance from bag overfill is within normal biological pharmacokinetic tolerances and pump delivery variance ($\pm 5\%$).
2. The app explicitly provides the total drug in milligrams ($60\text{ mg}$), the exact volume ($1.5\text{ mL}$), and the patient delivery rate in $\text{mcg/kg/min}$, giving the veterinarian full situational awareness.
3. Attempting to force manual bag measurement would cause far greater harm through septic shock than a minor pharmacologic dilution variance.
