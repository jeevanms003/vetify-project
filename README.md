# Vetifi Reference & Clinical Dose Calculator

Production-grade clinical dose calculator and signed dataset distribution platform designed for veterinarians in rural and low-connectivity environments.

---

## 1. Quick Setup & Execution

### Prerequisites
- **Flutter SDK**: 3.19.6 or later (Dart 3.3.4+)
- **Python**: 3.10+ (or Docker / Docker Compose)

---

### Running the Backend Service

#### Option A: Docker Compose (Recommended)
```bash
docker compose up --build
```
The server will start on `http://localhost:8000` with automatic SQLite/PostgreSQL persistence and pre-seeded `v14` base formulary.

#### Option B: Direct Python Execution
```bash
cd server
pip install -r requirements.txt
python -m uvicorn server.main:app --host 0.0.0.0 --port 8000 --reload
```

#### Running Server Integration Tests:
```bash
cd server
python -m unittest tests/test_server.py
```
*Covers 9 comprehensive test suites: seeding, Ed25519 verification, concurrent publish conflicts (409), delta combinations across versions, ETag 304 caching, calc log deduplication, and chaos simulations.*

---

### Running the Flutter Mobile / Desktop App

```bash
cd app
flutter pub get
flutter run
```

#### Running Flutter Unit & Clinical Tests:
```bash
cd app
flutter test
```
*Covers all dose calculation edge cases, microgram conversions, ceiling caps, biological weight sanity, CRI infusions, 50,000+ drug fuzzy search, and atomic update crash resilience.*

---

## 2. Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │          Vetifi Dataset Server         │
                      │  - FastAPI + SQLite / PostgreSQL       │
                      │  - Ed25519 Asymmetric Signer          │
                      │  - Concurrency Locking & Idempotency   │
                      │  - Multi-version Delta Combiner        │
                      └──────────────────┬─────────────────────┘
                                         │ Signed Manifest & Deltas
                                         ▼ (HTTP / ETag / Ed25519)
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Flutter Application                             │
│                                                                              │
│  ┌─────────────────────────┐  ┌───────────────────────┐  ┌─────────────────┐ │
│  │   Dose Calculator       │  │    CRI Infusion       │  │  Formulary 50k  │ │
│  │   - Unit normalizer     │  │    - Displacement     │  │  - Fuzzy search │ │
│  │   - Ceiling caps        │  │    - Duration hours   │  │  - Race guard   │ │
│  │   - Precision volumes   │  │    - Safety alerts    │  │  - Telemetry    │ │
│  └─────────────────────────┘  └───────────────────────┘  └─────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                       Dataset Repository & Security                     │ │
│  │  - Offline-first fallback to bundled v14 asset                          │ │
│  │  - Ed25519 public key verification & SHA-256 hash validation            │ │
│  │  - Atomic file swap: staging.tmp -> renameSync (Zero corruption)        │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                       Local Calculation Audit Logger                    │ │
│  │  - 100% offline local logging (Zero network calls at calc time)          │ │
│  │  - Asynchronous background synchronization to /v1/calc_logs             │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Key Technical Decisions

1. **Safety-First Fail-Closed Validation (Part A):**
   - Corrupted records (e.g. `Corvadil` min > max, `Quilomid` 0 mg/mL, `Pirovane` cat null) are blocked from calculation with explanatory clinical warnings.
   - Precise weight conversion: $1\text{ lb} = 0.45359237\text{ kg}$ rather than imprecise $\div 2.2$.
   - Neonatal dose preservation: Volumes $< 0.1\text{ mL}$ are formatted up to 3 decimal places with an explicit 1 mL syringe alert.

2. **Ranked Typo-Tolerant Search Across 50,000+ Drugs (Part B):**
   - 50,000 synthetic clinical drugs combined with formulary base.
   - Levenshtein approximate matching (`melokin` $\to$ `Meloquin`, `benzaprl` $\to$ `Benzaprol`).
   - Ranking hierarchy: Exact match (Rank 0) $\to$ Prefix (Rank 1) $\to$ Substring (Rank 2) $\to$ Fuzzy (Rank 3).
   - Monotonic token counter prevents out-of-order asynchronous search results from overwriting subsequent queries.

3. **Continuous Rate Infusion (CRI) Displacement Mathematics (Part C):**
   - Computes stock drug volume to add to bag and run time in hours.
   - Calculates fluid displacement percentage. When $\ge 2\%$, instructs the vet to withdraw fluid before compounding to prevent dilution underdosing.

4. **Cryptographic Updates & Concurrency Control (Part D & E):**
   - Manifest and payload signed using **Ed25519**. The client verifies against a static public key.
   - Concurrency conflicts: Two administrators publishing from the same base receive `409 Conflict`.
   - Atomic file write: Downloads write to `staging.tmp` and atomic OS rename ensures power-loss crash resilience.
   - Deduplicated calculation logs uploaded asynchronously with zero network requests at calculation time.

---

## 4. Completed Features Summary

- [x] **Part A: Dose Calculator** (Complete: offline baseline, weight parsing, comma support, biological bounds, microgram units, ceiling caps, impossible-to-misread UI).
- [x] **Part B: Search Engine** (Complete: 50,000+ drugs, Levenshtein typo tolerance, exact/prefix/fuzzy ranking, race condition immunity, latency telemetry).
- [x] **Part C: Constant Rate Infusion** (Complete: Dopraxine support, unit conversions, run time duration, fluid bag displacement analysis).
- [x] **Part D: Dataset Server** (Complete: FastAPI, Ed25519 signing, delta combiner, ETag 304, 409 conflict, idempotency, chaos mode, 9 integration tests).
- [x] **Part E: App Updates & Security** (Complete: Ed25519 verification, atomic file replacement, dataset version badge, persistent audit logging, async sync).
- [x] **Part F: Written Questions in `DECISIONS.md`** (Complete: all 6 questions answered concisely under 200 words).
- [x] **Part G: Code Review in `DECISIONS.md`** (Complete: Functions 1, 2, 3 reviewed, animal harm ranked, corrected Dart implementation written).
- [x] **Part H: Documentation & Audit Logs** (Complete: `README.md`, `DECISIONS.md`, `BREAK_IT.md`, `AI_LOG.md`).

---

## 5. Video Demonstration Guide (Part H.4)

For recording your 5-minute unedited walkthrough:
1. **Face & Screen Visible:** Open the Flutter app on desktop or Android emulator.
2. **Airplane Mode Offline Demonstration:**
   - Disconnect internet / toggle airplane mode.
   - Search for `Veloxamine` and calculate a 10 kg dog dose ($1.0\text{--}2.0\text{ mL}$).
   - Attempt to calculate `Corvadil` and `Quilomid` to show the safety locks refusing calculation.
   - Calculate small kitten dose ($0.07\text{ mL}$) showing the 1 mL syringe alert.
3. **Typo Search Demonstration:**
   - Type `melokin` $\to$ shows `Meloquin`.
   - Type `benzaprl` $\to$ shows `Benzaprol`.
   - Show live search latency ($< 30\text{ ms}$).
4. **Online Chaos Simulation:**
   - Reconnect network. Go to **Updates** tab.
   - Tap **1. Tampered Payload** $\to$ observe signature rejection banner.
   - Tap **2. Corrupted Hash** $\to$ observe SHA-256 mismatch rejection.
   - Tap **Check for Signed Updates** $\to$ successfully syncs from server.
5. **Least Confident Area:**
   - Conclude by discussing commercial IV fluid bag manufacturer overfill (as analyzed in `BREAK_IT.md`).
