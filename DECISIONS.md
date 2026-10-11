# DECISIONS.md

## Part F: Written Questions

### 1. Small Doses (0.07 mL kitten vs 38.4 mL dog & rounding rules)
For a 2.5 kg kitten requiring 0.07 mL, rounding to one decimal place yields 0.1 mL—a 42.8% relative overdose that can be fatal for narrow-therapeutic-index drugs (e.g., opioids, sedatives, insulin). Conversely, 0.04 mL would round to 0.0 mL (fatal underdosing). Our app displays `"0.07 mL"` with a mandatory leading zero, accompanied by a high-visibility clinical alert: *"Small volume alert (< 0.1 mL): Use a 1 mL tuberculin/insulin syringe or dilute with 0.9% NaCl"*.

For a 40 kg dog requiring 38.4 mL, the app displays `"38.4 mL"`. Because standard 20–60 mL syringes have 1 mL markings, a 0.05 mL rounding difference represents less than 0.13% error, which is clinically negligible.

The app strictly refuses to round whenever the relative error introduced by rounding exceeds 5% of the total dose, or whenever the total volume is below 0.1 mL. Under these rules, exact precision is preserved to protect neonatal and small-patient lives.

---

### 2. Missing Species Data ("Show dog dose with warning?")
The strongest argument for displaying the dog dose is emergency triage in remote settings: when a veterinarian has no internet connectivity and an animal is crashing, providing an empirical reference dose allows an experienced clinician to make a calculated off-label decision rather than being completely blocked.

**Decision: REJECT the suggestion entirely.**

Cats are biologically not small dogs. Feline physiology exhibits distinct hepatic glucuronidation deficiencies (e.g., lack of UDP-glucuronosyltransferase UGT1A6), rendering drugs like acetaminophen, permethrin, and specific NSAIDs lethal at canine doses. Under emergency cognitive overload, confirmation bias and tunnel vision frequently cause clinicians to overlook warning banners. Showing a canine dose on a feline screen creates a lethal single point of failure.

Our app displays: *"Calculation Refused: No dosage defined for Feline"*. Software must fail closed when animal life is at stake.

---

### 3. Bag Volume Displacement in Infusions
Adding a drug to a fluid bag increases total volume from $V_{\text{bag}}$ to $V_{\text{bag}} + V_{\text{drug}}$, diluting the final concentration if fluid is not withdrawn first:
$$\text{Dilution \%} = \frac{V_{\text{drug}}}{V_{\text{bag}} + V_{\text{drug}}} \times 100$$

**When it does NOT matter:**
Adding 1.5 mL Dopraxine to a 500 mL bag results in 501.5 mL (0.3% dilution). Commercial fluid bags have an intrinsic volume variance of $\pm 5\text{--}10\%$, and infusion pumps vary by $\pm 5\%$. Here, 0.3% error is clinically insignificant.

**When it DOES matter:**
Adding 20 mL of drug to a 100 mL bag produces 120 mL (16.7% dilution), causing clinically significant underdosing.

**App Behavior:**
The app calculates dilution percentage dynamically. If dilution $\ge 2\%$, the app displays: *"Displacement Alert: Withdraw X mL fluid before adding drug to maintain exact concentration"*. If $< 2\%$, it explicitly informs the user that displacement is clinically negligible.

---

### 4. Users Who Never Update (v14 Benzaprol Offline for 5 Months)
When an app remains offline for months, it cannot receive remote updates. To defend against outdated or erroneous data:

1. **Strict Format Validation:** In v14, Benzaprol has concentration `"10%"`. Our parser enforces unambiguous units. If an entry is ambiguous, calculation is blocked with an explanation.
2. **Formulary Expiration / TTL:** The app tracks dataset age against local device clock. When an offline dataset exceeds 30 days without sync, an persistent amber banner warns: *"Formulary v14 is 150 days old. Connect to Wi-Fi to synchronize safety updates"*.
3. **Hard Ceiling & Physiological Bounds:** Biological sanity checks reject impossible outputs.
4. **Explicit Concentration Confirmation:** When concentration strings are unconventional (e.g. percentages), the app prompts the clinician to confirm the milligram equivalent ($10\% = 100\text{ mg/mL}$) before calculating.

The software cannot create internet access, but it can stop an outdated record from quietly harming an animal.

---

### 5. Leaked Signing Key (Impact & Recovery)
**Attacker Capabilities:**
An attacker holding the Ed25519 private key can forge updates, inject lethal doses, and publish validly signed poisoned payloads. Installed apps would verify the signature and accept the malicious dataset.

**Current App Behavior:**
The app currently embeds a single Ed25519 public key. Therefore, installed apps cannot distinguish legitimate updates from attacker-signed updates without an application update.

**Recovery Procedure & Architectural Fix:**
1. **Immediate Revocation:** Publish a server-side notice and mark current endpoints in emergency read-only status.
2. **Emergency Store Release:** Ship an immediate app patch containing a new keypair.
3. **Architectural Redesign:**
   - **Multi-Signature (M-of-N):** Require 2 out of 3 independent clinical signing keys to approve any dataset publication.
   - **Key Hierarchy:** Implement a root offline key that signs short-lived intermediate release keys with expiration timestamps.
   - **Signed Key Revocation List (KRL):** Provide a secondary trust anchor capable of blacklisting compromised keys.

---

### 6. Limits of Design (When Storage/Search/Server Fails)
**Scenario Where Current Design Fails:**
A multi-hospital enterprise deployment managing 1,000,000+ formulary records, real-time drug interaction graphs, images, monographs, and 50,000 concurrent hospital terminals.

**Why Our Current Design Fails:**
1. **Client Storage & Search:** In-memory Levenshtein across 1,000,000 entries exhausts mobile RAM and introduces multi-second UI stutter. Bundling full snapshots in memory is infeasible.
2. **Server Delta Chains:** Replaying linear deltas across thousands of micro-versions becomes computationally expensive in relational SQLite/Postgres queries.

**What We Would Use Instead:**
1. **Client:** SQLite with `FTS5` (Full-Text Search) and trigram indexing, storing records on disk and querying via pagination and virtual tables.
2. **Server:** Distributed PostgreSQL with Elasticsearch / Meilisearch cluster for typo-tolerant fuzzy search.
3. **Sync:** Row-level Change Data Capture (CDC via Debezium/Kafka) and CRDT-based partition syncing.

---

## Part G: Code Review

### Function 1 (Dart)
```dart
double volumeMl(double weight, String unit, double dosePerKg, String concentration) {
  final kg = unit == 'lb' ? weight / 2.2 : weight;
  final mgPerMl = double.parse(concentration.split(' ')[0]);
  final doseMg = kg * dosePerKg;
  return double.parse((doseMg / mgPerMl).toStringAsFixed(1));
}
```
**Problems Identified:**
1. `concentration.split(' ')[0]` fails on percentage concentrations like `"10%"` (throws `FormatException` and crashes in an emergency) and fails on microgram concentrations (`"100 mcg/mL"` parsed as 100 mg/mL, resulting in a 1,000-fold underdose).
2. `toStringAsFixed(1)` rounds to 1 decimal place. For small animals (e.g. 0.07 mL), this yields 0.1 mL (a 43% overdose) or 0.0 mL (zero dose).
3. `weight / 2.2` introduces unnecessary conversion inaccuracy (exact: `weight * 0.45359237`).
4. Missing zero/negative/NaN validation on weight, concentration, and dose. Division by zero yields `Infinity`.

**Animal Harm Rank: 1 (Most Harmful)**
Directly causes fatal overdose or underdose through premature decimal rounding and concentration unit misparsing.

---

### Function 2 (Dart)
```dart
Future<void> applyUpdate(File file) async {
  final db = await openDb();
  await db.delete('drugs');
  final data = jsonDecode(await file.readAsString());
  for (final d in data['upserts']) {
    await db.insert('drugs', Drug.fromJson(d).toMap());
  }
  await prefs.setString('dataset_version', data['dataset_version']);
}
```
**Problems Identified:**
1. **Non-Atomic Wipeout:** Deletes the existing dataset (`db.delete('drugs')`) BEFORE reading or validating the file. If `file` contains invalid JSON or the app crashes during the loop, the database is left completely empty during an emergency.
2. **Missing Delta Handling:** Deletes all drugs, but only inserts `data['upserts']`. All unaffected formulary drugs are deleted and lost!
3. **Zero Cryptographic Verification:** No hash check or signature verification; vulnerable to tampering.
4. **Performance:** Individual un-batched inserts without a database transaction.

**Animal Harm Rank: 2 (Second Most Harmful)**
Can leave clinicians with an empty formulary in the middle of emergency patient care.

---

### Function 3 (Python, FastAPI)
```python
@app.post("/admin/datasets")
def publish(body: dict, x_admin_key: str = Header(None)):
  if x_admin_key != os.environ.get("ADMIN_KEY"):
    raise HTTPException(401)
  latest = db.execute("SELECT max(version) FROM datasets").scalar()
  new_version = f"v{int(latest[1:]) + 1}"
  db.execute(f"INSERT INTO datasets (version, payload) "
             f"VALUES ('{new_version}', '{json.dumps(body)}')")
  return {"version": new_version}
```
**Problems Identified:**
1. **SQL Injection:** Interpolates unescaped JSON string directly into SQL.
2. **Lexicographical Sort Bug:** `SELECT max(version)` sorts strings lexicographically (`'v9' > 'v14'`), causing version sequence corruption.
3. **Concurrency Race Condition:** No locking or transaction; simultaneous requests will generate duplicate version numbers.
4. **Zero Payload Validation:** Accepts inverted dose ranges and zero concentrations without checking.
5. **Timing Attack:** String equality check on `x_admin_key` is vulnerable to timing analysis.

**Animal Harm Rank: 3**
Enables administrative tampering and dataset corruption across the network.

---

### Corrected Code for Most Serious Issue (Function 1)
```dart
/// Calculates safe dose volume with strict unit parsing, biological validation,
/// ceiling caps, and non-destructive rounding.
double safeVolumeMl({
  required double weight,
  required String unit,
  required double dosePerKg,
  required String doseUnit,
  required String concentrationRaw,
  double? maxTotalMg,
}) {
  // 1. Validate inputs
  if (weight <= 0 || weight.isNaN || weight.isInfinite) {
    throw ArgumentError('Weight must be a positive finite number.');
  }
  if (dosePerKg <= 0 || dosePerKg.isNaN || dosePerKg.isInfinite) {
    throw ArgumentError('Dose per kg must be greater than zero.');
  }

  // 2. High-precision weight conversion
  const double lbToKg = 0.45359237;
  final double kg = unit.trim().toLowerCase() == 'lb' ? weight * lbToKg : weight;

  // 3. Parse stock concentration accurately
  final double mgPerMl = _parseConcentrationMgPerMl(concentrationRaw);

  // 4. Calculate dose in mg (handling mcg/kg vs mg/kg)
  double doseMg;
  final cleanDoseUnit = doseUnit.trim().toLowerCase();
  if (cleanDoseUnit == 'mg/kg') {
    doseMg = kg * dosePerKg;
  } else if (cleanDoseUnit == 'mcg/kg' || cleanDoseUnit == 'ug/kg') {
    doseMg = (kg * dosePerKg) / 1000.0;
  } else {
    throw ArgumentError('Unsupported dose unit: $doseUnit');
  }

  // 5. Apply ceiling cap if present
  if (maxTotalMg != null && maxTotalMg > 0 && doseMg > maxTotalMg) {
    doseMg = maxTotalMg;
  }

  // 6. Compute exact volume
  final double volume = doseMg / mgPerMl;

  // 7. Safe rounding: NEVER round small volumes to 1 decimal place!
  // Volumes < 0.1 mL are preserved to 3 decimal places for precision syringes.
  if (volume < 0.1) {
    return double.parse(volume.toStringAsFixed(3));
  } else if (volume < 1.0) {
    return double.parse(volume.toStringAsFixed(2));
  } else {
    return double.parse(volume.toStringAsFixed(2));
  }
}

double _parseConcentrationMgPerMl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) throw ArgumentError('Concentration cannot be empty.');

  // Handle percentages (e.g. 10% = 100 mg/mL)
  if (s.endsWith('%')) {
    final val = double.tryParse(s.substring(0, s.length - 1).trim());
    if (val == null || val <= 0) throw ArgumentError('Invalid percentage concentration: $raw');
    return val * 10.0;
  }

  final parts = s.split(RegExp(r'\s+'));
  final numVal = double.tryParse(parts[0]);
  if (numVal == null || numVal <= 0) {
    throw ArgumentError('Invalid concentration value: $raw');
  }

  if (parts.length > 1) {
    final unit = parts[1].toLowerCase();
    if (unit == 'mg/ml') return numVal;
    if (unit == 'mcg/ml' || unit == 'ug/ml') return numVal / 1000.0;
    if (unit == 'g/ml') return numVal * 1000.0;
  }

  return numVal;
}
```
