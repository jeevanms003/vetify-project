import re
from typing import Any, Dict, List, Optional, Tuple


def parse_version_number(version_str: str) -> Optional[int]:
    """Extracts integer from version strings like 'v14' -> 14."""
    if not version_str or not isinstance(version_str, str):
        return None
    match = re.match(r"^v(\d+)$", version_str.strip())
    if match:
        return int(match.group(1))
    return None


def parse_concentration(conc_str: str) -> Tuple[Optional[float], Optional[str]]:
    """
    Parses concentration strings such as '50 mg/mL', '1.5 mg/mL', '10%'.
    Returns (value_in_mg_per_ml, unit_string) or (None, None) if invalid.
    """
    if not conc_str or not isinstance(conc_str, str):
        return None, None

    s = conc_str.strip()

    # Percentage check: e.g. '10%' -> 10 g / 100 mL = 100 mg/mL
    pct_match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*%$", s)
    if pct_match:
        val = float(pct_match.group(1))
        return val * 10.0, "%"

    # mg/mL or mcg/mL or g/mL
    unit_match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]+(?:\/[a-zA-Z]+)?)$", s)
    if unit_match:
        val = float(unit_match.group(1))
        unit = unit_match.group(2)
        if unit.lower() in ["mg/ml", "mg/milliliter"]:
            return val, "mg/mL"
        elif unit.lower() in ["mcg/ml", "ug/ml"]:
            return val / 1000.0, "mcg/mL"
        elif unit.lower() in ["g/ml"]:
            return val * 1000.0, "g/mL"
        return val, unit

    return None, None


def validate_drug(drug: Dict[str, Any]) -> List[Dict[str, str]]:
    """
    Validates a single drug entry.
    Returns list of error objects: [{"drug_id": id, "field": field, "message": msg}]
    """
    errors: List[Dict[str, str]] = []
    drug_id = drug.get("id") or "UNKNOWN"

    def err(field: str, msg: str):
        errors.append({"drug_id": str(drug_id), "field": field, "message": msg})

    if not drug.get("id") or not isinstance(drug.get("id"), str):
        err("id", "Drug id is required and must be a non-empty string")

    name = drug.get("name")
    if not name or not isinstance(name, str) or not name.strip():
        err("name", "Drug name is required and cannot be empty")

    route = drug.get("route")
    if not route or not isinstance(route, str) or not route.strip():
        err("route", "Route is required and cannot be empty")

    concentration_raw = drug.get("concentration")
    if concentration_raw is None or not isinstance(concentration_raw, str):
        err("concentration", "Concentration is required and must be a string")
    else:
        conc_val, conc_unit = parse_concentration(concentration_raw)
        if conc_val is None:
            err("concentration", f"Unrecognized concentration format: '{concentration_raw}'")
        elif conc_val <= 0:
            err("concentration", f"Concentration must be strictly positive (> 0), got: '{concentration_raw}'")

    # Doses & CRI validation
    doses = drug.get("doses")
    cri = drug.get("cri")

    if doses is None and cri is None:
        err("doses", "Drug must define at least one dose specification (doses or cri)")

    if doses is not None:
        if not isinstance(doses, dict):
            err("doses", "doses must be a JSON object mapping species to dose ranges")
        else:
            for species, spec in doses.items():
                if spec is None:
                    continue  # null species dose is allowed (species not indicated)
                if not isinstance(spec, dict):
                    err(f"doses.{species}", f"Dose for species '{species}' must be an object or null")
                    continue
                min_val = spec.get("min")
                max_val = spec.get("max")
                unit = spec.get("unit")

                if min_val is None or not isinstance(min_val, (int, float)) or min_val <= 0:
                    err(f"doses.{species}.min", f"min dose must be a positive number (> 0), got {min_val}")
                if max_val is None or not isinstance(max_val, (int, float)) or max_val <= 0:
                    err(f"doses.{species}.max", f"max dose must be a positive number (> 0), got {max_val}")
                if (
                    isinstance(min_val, (int, float))
                    and isinstance(max_val, (int, float))
                    and min_val > max_val
                ):
                    err(f"doses.{species}", f"min dose ({min_val}) cannot be greater than max dose ({max_val})")
                if not unit or not isinstance(unit, str) or not unit.strip():
                    err(f"doses.{species}.unit", "unit must be a non-empty string (e.g. mg/kg, mcg/kg)")

    if cri is not None:
        if not isinstance(cri, dict):
            err("cri", "cri must be a JSON object mapping species to infusion rates")
        else:
            for species, spec in cri.items():
                if spec is None:
                    continue
                if not isinstance(spec, dict):
                    err(f"cri.{species}", f"CRI dose for species '{species}' must be an object or null")
                    continue
                min_val = spec.get("min")
                max_val = spec.get("max")
                unit = spec.get("unit")

                if min_val is None or not isinstance(min_val, (int, float)) or min_val <= 0:
                    err(f"cri.{species}.min", f"CRI min must be a positive number (> 0), got {min_val}")
                if max_val is None or not isinstance(max_val, (int, float)) or max_val <= 0:
                    err(f"cri.{species}.max", f"CRI max must be a positive number (> 0), got {max_val}")
                if (
                    isinstance(min_val, (int, float))
                    and isinstance(max_val, (int, float))
                    and min_val > max_val
                ):
                    err(f"cri.{species}", f"CRI min ({min_val}) cannot be greater than max ({max_val})")
                if not unit or not isinstance(unit, str) or not unit.strip():
                    err(f"cri.{species}.unit", "CRI unit must be a non-empty string (e.g. mcg/kg/min)")

    max_total = drug.get("max_total_mg")
    if max_total is not None:
        if not isinstance(max_total, (int, float)) or max_total <= 0:
            err("max_total_mg", f"max_total_mg must be a positive number, got {max_total}")

    return errors


def validate_dataset_payload(
    payload: Dict[str, Any],
    current_schema_version: int = 2,
) -> Tuple[bool, List[Dict[str, str]]]:
    """
    Validates payload syntax, schema version, and individual drug fields.
    """
    errors: List[Dict[str, str]] = []

    # 1. Schema version check
    schema_v = payload.get("schema_version")
    if schema_v != current_schema_version:
        errors.append({
            "drug_id": "GLOBAL",
            "field": "schema_version",
            "message": f"Expected schema_version {current_schema_version}, got {schema_v}",
        })

    # 2. Dataset version format check
    target_version = payload.get("dataset_version")
    target_num = parse_version_number(target_version)
    if target_num is None:
        errors.append({
            "drug_id": "GLOBAL",
            "field": "dataset_version",
            "message": f"Invalid dataset_version format: '{target_version}'. Must be 'v<number>'",
        })

    # 3. Drugs validation
    if "drugs" in payload:
        drugs = payload.get("drugs")
        if not isinstance(drugs, list):
            errors.append({"drug_id": "GLOBAL", "field": "drugs", "message": "drugs must be a list"})
        else:
            for drug in drugs:
                errors.extend(validate_drug(drug))

    # 4. Upserts validation
    if "upserts" in payload:
        upserts = payload.get("upserts")
        if not isinstance(upserts, list):
            errors.append({"drug_id": "GLOBAL", "field": "upserts", "message": "upserts must be a list"})
        else:
            for drug in upserts:
                errors.extend(validate_drug(drug))

    # 5. Withdrawn validation
    if "withdrawn" in payload:
        withdrawn = payload.get("withdrawn")
        if not isinstance(withdrawn, list):
            errors.append({"drug_id": "GLOBAL", "field": "withdrawn", "message": "withdrawn must be a list"})
        else:
            for drug_id in withdrawn:
                if not isinstance(drug_id, str) or not drug_id.strip():
                    errors.append({
                        "drug_id": str(drug_id),
                        "field": "withdrawn",
                        "message": "Withdrawn drug ID must be a non-empty string",
                    })

    return len(errors) == 0, errors
