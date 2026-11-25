#!/usr/bin/env python3
"""Normalise every authored standalone curve asset (``UCurveFloat`` /
``UCurveLinearColor`` / ``UCurveVector``) into the ``tables/**`` tree so the
runtime roots in ``game/src/core/game_data.gd`` stop being empty.

Why this exists (RE-A-01): the extractor dumps curve *assets* as generic
property JSON, and ``parse_tables.py`` only normalises
``DataTable|CurveTable|CompositeDataTable|StringTable`` exports. The runtime
therefore asked for nine extra curve directories of which five did not exist:

    tables/Gameplay/Input/Character
    tables/Gameplay/Traversal/Dodge
    tables/AI/Alertness
    tables/Gameplay/Carry
    tables/Art/Environment/Weather

Those five, plus ``AI/Data`` and ``Character/Player``, are exactly where the
top-level curve assets live, so simply emitting them fills every dead root.

Scope, measured on the W7 tree (2026-11-25):

* **16 standalone curve assets** (14 ``CurveFloat`` + 2 ``CurveLinearColor``)
  whose export ``Name`` equals its ``Package`` stem. These are emitted as one
  JSON per asset under ``tables/<package dir>/<Name>.json`` and are picked up by
  the existing loader with no GDScript change (``_store_table_file`` treats any
  row dictionary containing ``Keys`` as a curve).
* **108 curve objects nested inside Blueprint packages** (99 ``CurveFloat``, 6
  ``CurveVector``, 3 ``CurveLinearColor``). These are component defaults, not
  assets; they are indexed in ``curves.json`` (with their owning package and
  key count) so nothing is silently dropped, but no fake table file is written.
* **23 ``CurveTable`` assets** are *already* normalised 1:1 by
  ``parse_tables.py`` (18 ``CT_*`` + 5 ``Curve_*_Table``). This producer never
  writes them; it counts them so the numbers in ``curves.json`` reconcile.

Output contract
---------------

``<out-dir>/tables/<pkg-dir>/<Name>.json`` (one per standalone curve)::

    {
      "type": "CurveFloat" | "CurveLinearColor" | "CurveVector",
      "name": "Curve_Dodge",
      "asset": "/Game/Gameplay/Traversal/Dodge/Curve_Dodge",
      "rows": {
        "Value": {                      # float  -> "Value"
          "Keys": [                     # colour -> "R","G","B","A"
            {"Time": 0.0, "Value": 0.0,  # vector -> "X","Y","Z"
             "InterpMode": "RCIM_Linear",
             "TangentMode": "RCTM_Auto",
             "TangentWeightMode": "RCTWM_WeightedNone",
             "ArriveTangent": 0.0, "ArriveTangentWeight": 0.0,
             "LeaveTangent": 0.0, "LeaveTangentWeight": 0.0}
          ]
        }
      },
      "channels": ["Value"],            # authored channels actually present
      "sparse_channels": [],            # e.g. a vector whose X/Y are absent
      "key_count": 4,
      "time_range": [0.0, 1.0]
    }

Row names are channel names, so a consumer reads::

    GameData.eval_curve("Curve_Dodge", "Value", x)
    GameData.eval_curve("C_Sky_Gradient", "R", t)

``InterpMode`` is the **outgoing segment** mode of the key it is stored on (UE
semantics: the mode on key *i* governs the segment [key i, key i+1)). It is
emitted so a consumer can honour ``RCIM_Constant`` without re-reading the raw
dump; the current ``GameData.eval_curve`` always lerps and ignores it.

``<out-dir>/curves.json`` (index + reconciliation)::

    {
      "schema": "tat2.curves/1",
      "generated_by": "tools/parse_curves.py",
      "source": "extracted/json/**",
      "counts": {
        "standalone": 16, "nested": 108, "curve_tables": 23, "emitted": 16,
        "standalone_by_type": {"CurveFloat": 14, "CurveLinearColor": 2},
        "nested_by_type": {"CurveFloat": 99, "CurveVector": 6,
                           "CurveLinearColor": 3}
      },
      "standalone": [
        {"asset": "/Game/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier",
         "name": "Curve_AI_HeightDifferenceToStrengthMultiplier",
         "type": "CurveFloat",
         "table": "res://data/generated/tables/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json",
         "channels": ["Value"], "key_count": 2, "time_range": [2.0, 3.0]}
      ],
      "nested": [
        {"owner": "/Game/Art/Environment/Props/Kitchen/BP_Dumbwaiter",
         "name": "CurveVector_0", "type": "CurveVector",
         "dump": "extracted/json/Art/Environment/Props/Kitchen/BP_Dumbwaiter.json",
         "channels": ["Z"], "key_count": 2,
         "emitted": false, "reason": "blueprint sub-object default"}
      ]
    }

Deterministic: every list is sorted and no timestamp is written, because
``tools/audit_baseline.json`` pins the SHA-256 of the produced bytes.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CURVE_TYPES = ("CurveFloat", "CurveLinearColor", "CurveVector")
# UE packs multi-channel curves as FloatCurves, FloatCurves[1], FloatCurves[2]...
CHANNELS = {
    "CurveFloat": ("Value",),
    "CurveLinearColor": ("R", "G", "B", "A"),
    "CurveVector": ("X", "Y", "Z"),
}
# Per-key fields copied verbatim when authored (SimpleCurves mode omits them).
KEY_FIELDS = (
    "InterpMode",
    "TangentMode",
    "TangentWeightMode",
    "ArriveTangent",
    "ArriveTangentWeight",
    "LeaveTangent",
    "LeaveTangentWeight",
)


def _load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        return None


def _curve_channels(properties: dict) -> list[tuple[int, dict]]:
    """Split ``FloatCurve`` / ``FloatCurves`` / ``FloatCurves[n]`` into rows.

    ``UCurveFloat`` serialises one ``FloatCurve`` struct; ``UCurveLinearColor``
    and ``UCurveVector`` serialise one struct per channel under ``FloatCurves``
    (index 0) and ``FloatCurves[n]`` (index n > 0).
    """
    rows: list[tuple[int, dict]] = []
    for suffix, value in properties.items():
        if suffix in ("FloatCurve", "FloatCurves"):
            index = 0
        elif suffix.startswith("FloatCurves[") and suffix.endswith("]"):
            try:
                index = int(suffix[len("FloatCurves[") : -1])
            except ValueError:
                raise SystemExit("unparseable curve channel key %r" % suffix)
        else:
            continue
        if not isinstance(value, dict):
            raise SystemExit("curve channel %r is not a struct: %r" % (suffix, value))
        if not value:
            # An unauthored channel serialises as {} (e.g. the alpha channel of
            # C_Sky_Gradient). Absent, not malformed: record it as sparse.
            rows.append((index, {}))
            continue
        if "Keys" not in value:
            raise SystemExit("curve channel %r has no Keys" % suffix)
        rows.append((index, value))
    rows.sort(key=lambda item: item[0])
    return rows


def _normalise_keys(channel: dict, asset: str, suffix: str) -> list[dict]:
    keys = []
    for raw in channel.get("Keys") or ():
        if "Time" not in raw or "Value" not in raw:
            raise SystemExit(
                "curve %s %s: key without Time/Value: %r" % (asset, suffix, raw)
            )
        key = {"Time": float(raw["Time"]), "Value": float(raw["Value"])}
        for field in KEY_FIELDS:
            if field in raw:
                key[field] = raw[field]
        keys.append(key)
    return keys


def _standalone_record(export: dict, pkg: str) -> dict:
    curve_type = export["Type"]
    name = export["Name"]
    properties = export.get("Properties") or {}
    channel_names = CHANNELS[curve_type]
    channels = _curve_channels(properties)
    if not channels:
        raise SystemExit("curve %s (%s) has no FloatCurves data" % (pkg, curve_type))
    rows: dict[str, dict] = {}
    present: list[str] = []
    keys_by_channel: list[list[dict]] = []
    for index, channel in channels:
        if index >= len(channel_names):
            raise SystemExit(
                "curve %s (%s): channel index %d out of range for a %s"
                % (pkg, curve_type, index, curve_type)
            )
        row_name = channel_names[index]
        if not channel:
            continue
        keys = _normalise_keys(channel, pkg, row_name)
        if not keys:
            # Authored-but-empty channel: absent data, recorded via
            # ``sparse_channels`` below.
            continue
        rows[row_name] = {"Keys": keys}
        present.append(row_name)
        keys_by_channel.append(keys)
    if not rows:
        raise SystemExit("curve %s (%s) has no authored keys" % (pkg, curve_type))
    # A multi-channel curve may legitimately author only some channels: the raw
    # dump keeps the UE channel index (e.g. only FloatCurves[2] for a Vector),
    # so a missing lower index is a sparse channel, not a parse failure.
    highest = max(index for index, _ in channels)
    sparse = [
        channel_names[i] for i in range(highest + 1) if channel_names[i] not in present
    ]
    key_count = sum(len(k) for k in keys_by_channel)
    times = [k["Time"] for keys in keys_by_channel for k in keys]
    return {
        "type": curve_type,
        "name": name,
        "asset": pkg,
        "rows": rows,
        "channels": present,
        "sparse_channels": sparse,
        "key_count": key_count,
        "time_range": [min(times), max(times)],
    }


def _rel_table_path(pkg: str, name: str) -> Path:
    prefix = "/Game/"
    if not pkg.startswith(prefix):
        raise SystemExit("package %r is not under /Game/" % pkg)
    rel = pkg[len(prefix) :].rsplit("/", 1)
    parts = [p for p in rel[0].split("/") if p]
    return Path(*parts) / (name + ".json")


def collect(extracted: Path) -> tuple[list[dict], list[dict], int]:
    """Return (standalone curves, nested curves, CurveTable count)."""
    json_root = extracted / "json"
    if not json_root.is_dir():
        raise SystemExit("missing extracted JSON tree: %s" % json_root)
    standalone: list[dict] = []
    nested: list[dict] = []
    curve_tables = 0
    for dump in sorted(json_root.rglob("*.json")):
        data = _load(dump)
        if not isinstance(data, list):
            continue
        for export in data:
            if not isinstance(export, dict):
                continue
            kind = export.get("Type")
            if kind == "CurveTable":
                curve_tables += 1
                continue
            if kind not in CURVE_TYPES:
                continue
            pkg = export.get("Package") or ""
            name = export.get("Name") or ""
            if not name:
                raise SystemExit("curve export without Name in %s" % dump)
            if not pkg:
                # A nested curve object keeps only its Outer reference
                # (/Game/.../BP_X.0); the owning package is that path minus
                # the export index.
                outer = (export.get("Outer") or {}).get("ObjectPath") or ""
                if not outer:
                    raise SystemExit(
                        "curve export %s has neither Package nor Outer in %s"
                        % (name, dump)
                    )
                pkg = outer.rsplit(".", 1)[0]
            if pkg.rsplit("/", 1)[-1] == name:
                record = _standalone_record(export, pkg)
                record["source_dump"] = str(dump.relative_to(extracted.parent))
                standalone.append(record)
            else:
                channels = _curve_channels(export.get("Properties") or {})
                key_count = sum(len(c.get("Keys", ())) for _, c in channels)
                channel_names = CHANNELS[kind]
                present = [
                    channel_names[i] for i, _ in channels if i < len(channel_names)
                ]
                nested.append(
                    {
                        "owner": pkg,
                        "name": name,
                        "type": kind,
                        "dump": str(dump.relative_to(extracted.parent)),
                        "channels": present,
                        "key_count": key_count,
                        "emitted": False,
                        "reason": "blueprint sub-object default",
                    }
                )
    standalone.sort(key=lambda r: r["asset"])
    nested.sort(key=lambda r: (r["owner"], r["name"]))
    return standalone, nested, curve_tables


def write_outputs(extracted: Path, out_dir: Path, quiet: bool) -> tuple[int, int, int]:
    standalone, nested, curve_tables = collect(extracted)
    tables_root = out_dir / "tables"
    written = 0
    for record in standalone:
        rel = _rel_table_path(record["asset"], record["name"])
        target = tables_root / rel
        if target.exists():
            existing = _load(target)
            if isinstance(existing, dict) and existing.get("type") == "CurveTable":
                raise SystemExit(
                    "refusing to overwrite CurveTable %s with a %s"
                    % (target, record["type"])
                )
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "type": record["type"],
            "name": record["name"],
            "asset": record["asset"],
            "rows": record["rows"],
            "channels": record["channels"],
            "sparse_channels": record["sparse_channels"],
            "key_count": record["key_count"],
            "time_range": record["time_range"],
        }
        target.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        record["table"] = "res://data/generated/tables/" + rel.as_posix()
        written += 1

    by_type: dict[str, int] = {}
    for record in standalone:
        by_type[record["type"]] = by_type.get(record["type"], 0) + 1
    nested_by_type: dict[str, int] = {}
    for record in nested:
        nested_by_type[record["type"]] = nested_by_type.get(record["type"], 0) + 1

    index = {
        "schema": "tat2.curves/1",
        "generated_by": "tools/parse_curves.py",
        "source": "extracted/json/**",
        "counts": {
            "standalone": len(standalone),
            "nested": len(nested),
            "curve_tables": curve_tables,
            "emitted": written,
            "standalone_by_type": dict(sorted(by_type.items())),
            "nested_by_type": dict(sorted(nested_by_type.items())),
        },
        "standalone": standalone,
        "nested": nested,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "curves.json").write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if not quiet:
        print(
            "curves: %d standalone (%s) -> %d table files, %d nested indexed, "
            "%d CurveTables already normalised by parse_tables.py"
            % (
                len(standalone),
                ", ".join(f"{k} {v}" for k, v in sorted(by_type.items())),
                written,
                len(nested),
                curve_tables,
            )
        )
        for record in standalone:
            print(
                "  %-58s %-17s %2d keys  %s"
                % (
                    record["asset"],
                    record["type"],
                    record["key_count"],
                    ",".join(record["channels"]),
                )
            )
    return len(standalone), written, len(nested)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extracted", default=str(ROOT / "extracted"))
    parser.add_argument("--out-dir", default=str(ROOT / "game/data/generated"))
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    standalone, written, nested = write_outputs(
        Path(args.extracted), Path(args.out_dir), args.quiet
    )
    if standalone != written:
        print(
            "ERROR: %d standalone curves but %d files written" % (standalone, written),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
