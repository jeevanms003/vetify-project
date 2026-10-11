# AI_LOG.md

## Transparency in AI-Assisted Engineering

As requested by the Vetifi founding team, this log provides an honest, granular breakdown of AI utilization, failure modes encountered, unsafe AI suggestions rejected, and design decisions reconsidered.

---

### 1. AI Tools Used and Purposes
- **Gemini 3.6 Flash & Anthropic Claude 3.5 Sonnet:** Used for rapid structural scaffolding of boilerplate Flutter widgets, FastAPI routing templates, and generating unit test harnesses.
- **Interactive Shell / IDE Automation:** Used for executing test suites, benchmarking search latencies, and file organization.

---

### 2. Honest Estimate of Code Generation
- **Scaffolding & Boilerplate:** ~65% generated with AI assistance (e.g. Flutter widget hierarchies, standard SQLite table definitions, FastAPI route decorators).
- **Clinical Math & Cryptography:** 100% human-verified and re-architected. All dose calculation algorithms, unit conversions ($\text{mcg} \to \text{mg}$, $\text{lb} \to \text{kg}$), Ed25519 canonical JSON serialization, and atomic transaction file swapping were strictly written and reviewed by engineering judgment.

---

### 3. Two Cases Where the AI was Wrong or Unsafe

#### Case 1: Premature Rounding on Neonatal Patient Doses
- **The Prompt:**
  > *"Write a Dart helper function to calculate and format the drug volume in mL for display on the screen."*
- **The Unsafe AI Response:**
  ```dart
  double calculateVolume(double doseMg, double concentrationMgPerMl) {
    final rawVolume = doseMg / concentrationMgPerMl;
    // Format to 1 decimal place for clean user display
    return double.parse(rawVolume.toStringAsFixed(1));
  }
  ```
- **Why it was Unsafe:**
  For a 2.5 kg kitten requiring 0.07 mL, `(0.07).toStringAsFixed(1)` returns `0.1`—a **42.8% lethal overdose**. For 0.04 mL, it returns `0.0` (complete dose omission). The AI prioritized aesthetic UI brevity over clinical pharmacology.
- **What We Did Instead:**
  We implemented non-destructive decimal precision. Volumes $< 0.1\text{ mL}$ are strictly displayed to 3 decimal places (e.g. `0.07 mL`, never omitting leading zeros), and trigger an active clinical warning instructing the clinician to use a 1 mL tuberculin/insulin syringe or dilute with 0.9% sterile saline.

---

#### Case 2: Naive Concentration String Parsing
- **The Prompt:**
  > *"Parse the drug concentration string to get the mg/mL number for calculation."*
- **The Unsafe AI Response:**
  ```dart
  final mgPerMl = double.parse(concentration.split(' ')[0]);
  ```
- **Why it was Unsafe:**
  1. For Benzaprol in v14 (`"10%"`), `split(' ')[0]` returns `"10%"`. Passing `"10%"` into `double.parse()` throws an uncaught `FormatException`, crashing the application in the middle of emergency clinical care.
  2. For microgram concentrations like `"100 mcg/mL"`, it parses `100.0`, treating micrograms as milligrams—resulting in a **1,000-fold underdose**.
- **What We Did Instead:**
  We built a dedicated regex-based concentration parser supporting percentage w/v solutions ($10\% = 100\text{ mg/mL}$) and microgram units ($\text{mcg/mL} = 0.001\text{ mg/mL}$), with strict rejection of non-positive ($0\text{ mg/mL}$) or unparseable formats.

---

### 4. One Decision We Changed Our Mind About

#### Initial Approach:
When analyzing `d010` (Dravexin) with keys `{"Dog": ..., "feline": ...}`, our initial instinct was to write an ad-hoc dictionary patch:
```dart
if (key == 'feline') key = 'cat';
```

#### Why We Changed Our Mind:
The prompt explicitly mandated:
> *"Your app will also be tested against other datasets with the same structure, so please do not write fixes for individual entries."*

Writing entry-specific string replacements creates brittle software that silently breaks on future pipeline exports. Instead of hardcoded patches, we designed a **canonical species normalizer** (`normalizeSpeciesKey`) that lowercases and maps standard veterinary biological synonyms (`canine` $\to$ `dog`, `feline` $\to$ `cat`). Furthermore, if a dataset genuinely lacks data for an unmapped species, the calculator refuses to calculate and surfaces the exact missing key rather than silently guessing.
