#!/usr/bin/env python3
"""Deterministic baseline verification for clip_1795033698901.

Usage:
    /usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py

Runs eight checks over the canonical baseline artifacts and prints one
[PASS]/[FAIL] line per check followed by an "N/8 [PASS]" summary. Exit code is
0 only when all eight checks pass.

  1. Timeline continuity   BREAKDOWN.md S01-S27 vs KEYFRAME_INDEX.md section 2
  2. Template completeness every segment carries the 7 required subsections
  3. Image integrity       every linked JPEG opens at 1920x1080; size/folder caps
  4. Callout parity        callout_spec.json vs CALLOUT_LEGENDS.md row counts
  5. Timestamp parity      identical KF timestamps across all four sources
  6. Code taxonomy         observation codes + category/prefix agreement
  7. Cross-ref IDs         PG / HL / subsystem ranges and parity status set
  8. Determinism           re-render into a temp dir, compare SHA-256 digests

Stdlib + Pillow only. No randomness, no timestamps, no network access. The
clip directory is derived from this file's location, so the result does not
depend on the working directory.
"""

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

CLIP_DIR = Path(__file__).resolve().parent.parent
BREAKDOWN_PATH = CLIP_DIR / "BREAKDOWN.md"
KEYFRAME_INDEX_PATH = CLIP_DIR / "KEYFRAME_INDEX.md"
LEGENDS_PATH = CLIP_DIR / "CALLOUT_LEGENDS.md"
SPEC_PATH = CLIP_DIR / "callout_spec.json"
CLEAN_DIR = CLIP_DIR / "clean"
ANNOTATED_DIR = CLIP_DIR / "annotated"
RENDERER_PATH = CLIP_DIR / "tools" / "render_annotations.py"

SEGMENT_IDS = ["S%02d" % i for i in range(1, 28)]
EXPECTED_SUBSECTIONS = [
    "Narrative",
    "Visual",
    "HUD / UI",
    "Gameplay and interactions",
    "Audio",
    "TAT-2 cross-reference",
    "What to check in the port recording",
]

TAXONOMY = {}
for _i in range(1, 8):
    TAXONOMY["V%d" % _i] = "Visual"
for _i in range(1, 6):
    TAXONOMY["UI%d" % _i] = "HUD/UI"
for _i in range(1, 6):
    TAXONOMY["G%d" % _i] = "Gameplay/Audio"
for _i in range(1, 7):
    TAXONOMY["AU%d" % _i] = "Gameplay/Audio"

STAMP_RE = re.compile(r"\d{2}:\d{2}\.\d{2}")
CODE_TOKEN_RE = re.compile(r"(?<![A-Za-z0-9])(?:V|UI|G|AU)\d+(?![0-9])")
IMAGE_LINK_RE = re.compile(r"\]\((clean/[^)]+\.jpg|annotated/[^)]+\.jpg)\)")
PARITY_STATUS_RE = re.compile(
    r"^(?:1:1_MATCH|APPROX_SHADER|UNVERIFIED_LIVE|NOT_IMPLEMENTED"
    r"|KNOWN_GAP \(PG-\d+\)|HARD_LIMIT \(HL-\d+\))$"
)

IMAGE_SIZE = (1920, 1080)
ANNOTATED_MAX_BYTES = 750 * 1024
FOLDER_MAX_BYTES = 25 * 1024 * 1024


class CheckFailure(Exception):
    pass


def read_text(path):
    return path.read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise CheckFailure(message)


def sha256_of(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def split_sections(text, heading_prefix):
    return re.split(r"^%s[^\n]*$" % re.escape(heading_prefix), text, flags=re.M)


def breakdown_segments(text):
    segments = {}
    for line in text.splitlines():
        match = re.match(r"^## (S\d{2}) ", line)
        if not match:
            continue
        stamps = STAMP_RE.findall(line)
        require(
            len(stamps) == 2,
            "BREAKDOWN heading %s does not carry exactly two boundary stamps: %r"
            % (match.group(1), line),
        )
        segments[match.group(1)] = (stamps[0], stamps[1])
    return segments


def index_segments(text):
    section = split_sections(text, "## 2. Complete Continuous Segment Table")[1]
    section = section.split("\n## ", 1)[0]
    segments = {}
    for line in section.splitlines():
        match = re.match(
            r"^\|\s*\*\*(S\d{2})\*\*\s*\|\s*`(\d{2}:\d{2}\.\d{2})`"
            r"\s*\|\s*`(\d{2}:\d{2}\.\d{2})`",
            line,
        )
        if match:
            segments[match.group(1)] = (match.group(2), match.group(3))
    return segments


def index_keyframes(text):
    section = split_sections(text, "## 3. Keyframe Extraction Table")[1]
    section = section.split("\n## ", 1)[0]
    frames = {}
    for line in section.splitlines():
        match = re.match(
            r"^\|\s*`(KF\d{2})`\s*\|\s*`(\d{2}:\d{2}\.\d{2})`"
            r"\s*\|\s*`(S\d{2})`\s*\|\s*`([^`]+\.jpg)`",
            line,
        )
        if match:
            frames[match.group(1)] = {
                "timestamp": match.group(2),
                "segment": match.group(3),
                "filename": match.group(4),
            }
    return frames


def breakdown_keyframes(text):
    frames = {}
    for line in text.splitlines():
        if not line.startswith("**Keyframes:**"):
            continue
        for keyframe, stamp in re.findall(r"(KF\d{2})\s*\(`([^`]+)`\)", line):
            require(
                keyframe not in frames,
                "BREAKDOWN lists %s more than once" % keyframe,
            )
            frames[keyframe] = stamp
    return frames


def legend_sections(text):
    sections = {}
    parts = re.split(r"^### (KF\d{2}) - ", text, flags=re.M)
    for position in range(1, len(parts), 2):
        keyframe = parts[position]
        body = parts[position + 1].split("\n### ", 1)[0]
        stamp = re.search(r"^\((\d{2}:\d{2}\.\d{2}),\s*(S\d{2})\)\s*$", body, re.M)
        require(stamp is not None, "CALLOUT_LEGENDS %s has no timestamp line" % keyframe)
        rows = []
        for line in body.splitlines():
            row = re.match(r"^\|\s*(\d+)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|", line)
            if row:
                rows.append((int(row.group(1)), row.group(2), row.group(3)))
        sections[keyframe] = {
            "timestamp": stamp.group(1),
            "segment": stamp.group(2),
            "rows": rows,
        }
    return sections


def check_timeline_continuity():
    breakdown = breakdown_segments(read_text(BREAKDOWN_PATH))
    index = index_segments(read_text(KEYFRAME_INDEX_PATH))
    require(
        list(breakdown) == SEGMENT_IDS,
        "BREAKDOWN does not define exactly S01-S27 (found %s)" % sorted(breakdown),
    )
    require(
        list(index) == SEGMENT_IDS,
        "KEYFRAME_INDEX section 2 does not define exactly S01-S27 (found %s)"
        % sorted(index),
    )
    for segment in SEGMENT_IDS:
        require(
            breakdown[segment] == index[segment],
            "%s boundary mismatch: BREAKDOWN %s vs KEYFRAME_INDEX %s"
            % (segment, breakdown[segment], index[segment]),
        )
    for label, table in (("BREAKDOWN", breakdown), ("KEYFRAME_INDEX", index)):
        for position in range(len(SEGMENT_IDS) - 1):
            current = table[SEGMENT_IDS[position]]
            following = table[SEGMENT_IDS[position + 1]]
            require(
                current[1] == following[0],
                "%s %s ends at %s but %s starts at %s"
                % (label, SEGMENT_IDS[position], current[1], SEGMENT_IDS[position + 1], following[0]),
            )
    require(
        breakdown[SEGMENT_IDS[0]][0] == "00:00.00",
        "timeline starts at %s instead of 00:00.00" % breakdown[SEGMENT_IDS[0]][0],
    )
    require(
        breakdown[SEGMENT_IDS[-1]][1] == "03:45.64",
        "timeline ends at %s instead of 03:45.64" % breakdown[SEGMENT_IDS[-1]][1],
    )
    return "27 segments S01-S27, boundaries identical in both docs, 00:00.00..03:45.64 contiguous"


def check_template_completeness():
    text = read_text(BREAKDOWN_PATH)
    blocks = re.split(r"^## (S\d{2}) ", text, flags=re.M)
    found = {}
    for position in range(1, len(blocks), 2):
        found[blocks[position]] = blocks[position + 1]
    require(
        list(found) == SEGMENT_IDS,
        "BREAKDOWN does not define exactly S01-S27 (found %s)" % sorted(found),
    )
    for segment in SEGMENT_IDS:
        body = found[segment].split("\n## ", 1)[0]
        titles = re.findall(r"^### (.*)$", body, re.M)
        require(
            titles == EXPECTED_SUBSECTIONS,
            "%s subsections %s != expected %s" % (segment, titles, EXPECTED_SUBSECTIONS),
        )
    return "27/27 segments carry all 7 '### ' subsections in order"


def image_folder_files(folder):
    return sorted(p.name for p in folder.glob("*.jpg"))


def check_image_integrity():
    breakdown = read_text(BREAKDOWN_PATH)
    legends = read_text(LEGENDS_PATH)
    index = read_text(KEYFRAME_INDEX_PATH)
    links = set(IMAGE_LINK_RE.findall(breakdown)) | set(IMAGE_LINK_RE.findall(legends))
    for frame in index_keyframes(index).values():
        links.add("clean/" + frame["filename"])
        links.add("annotated/" + frame["filename"])
    require(links, "no linked JPEGs found in the reference documents")
    for relative in sorted(links):
        path = CLIP_DIR / relative
        require(path.is_file(), "linked image missing: %s" % relative)
        require(path.stat().st_size > 0, "linked image is empty: %s" % relative)
        try:
            with Image.open(path) as image:
                image.load()
                size = image.size
        except Exception as error:
            raise CheckFailure("PIL cannot open %s: %s" % (relative, error))
        require(
            size == IMAGE_SIZE,
            "%s is %dx%d instead of 1920x1080" % (relative, size[0], size[1]),
        )
        with path.open("rb") as handle:
            handle.seek(-2, 2)
            trailer = handle.read(2)
        require(
            trailer == b"\xff\xd9",
            "%s carries trailing bytes after the JPEG end-of-image marker" % relative,
        )
    clean = image_folder_files(CLEAN_DIR)
    annotated = image_folder_files(ANNOTATED_DIR)
    require(len(clean) == 30, "clean/ holds %d JPEGs instead of 30" % len(clean))
    require(len(annotated) == 30, "annotated/ holds %d JPEGs instead of 30" % len(annotated))
    require(
        clean == annotated,
        "clean/ and annotated/ filenames differ: only-clean=%s only-annotated=%s"
        % (sorted(set(clean) - set(annotated)), sorted(set(annotated) - set(clean))),
    )
    for name in annotated:
        size = (ANNOTATED_DIR / name).stat().st_size
        require(
            size < ANNOTATED_MAX_BYTES,
            "annotated/%s is %d bytes, not below 750KB" % (name, size),
        )
    for folder in (CLEAN_DIR, ANNOTATED_DIR):
        total = sum(p.stat().st_size for p in folder.iterdir() if p.is_file())
        require(
            total <= FOLDER_MAX_BYTES,
            "folder %s is %.2f MiB, above 25 MiB" % (folder.name, total / 1048576.0),
        )
    return "%d linked JPEGs valid at 1920x1080, clean/ == annotated/ (30 files), annotated max %d KB, folders under 25 MiB" % (
        len(links),
        max((ANNOTATED_DIR / name).stat().st_size for name in annotated) // 1024,
    )


def check_callout_parity():
    spec = json.loads(read_text(SPEC_PATH))
    frames = spec["keyframes"]
    legends = legend_sections(read_text(LEGENDS_PATH))
    require(
        sorted(frames) == sorted(legends),
        "keyframe sets differ: spec-only=%s legends-only=%s"
        % (sorted(set(frames) - set(legends)), sorted(set(legends) - set(frames))),
    )
    total = 0
    for keyframe in sorted(frames):
        spec_ids = [callout["id"] for callout in frames[keyframe]["callouts"]]
        legend_ids = [row[0] for row in legends[keyframe]["rows"]]
        require(
            spec_ids == list(range(1, len(spec_ids) + 1)),
            "callout_spec %s badge ids %s are not 1..N" % (keyframe, spec_ids),
        )
        require(
            legend_ids == list(range(1, len(legend_ids) + 1)),
            "CALLOUT_LEGENDS %s badge ids %s are not 1..N" % (keyframe, legend_ids),
        )
        require(
            len(spec_ids) == len(legend_ids),
            "%s callout count %d != legend row count %d"
            % (keyframe, len(spec_ids), len(legend_ids)),
        )
        total += len(spec_ids)
    return "%d keyframes, %d callouts, spec counts == legend row counts, badge ids 1..N contiguous" % (
        len(frames),
        total,
    )


def check_timestamp_parity():
    spec = json.loads(read_text(SPEC_PATH))
    spec_stamps = {kf: frame["timestamp"] for kf, frame in spec["keyframes"].items()}
    index_stamps = {kf: f["timestamp"] for kf, f in index_keyframes(read_text(KEYFRAME_INDEX_PATH)).items()}
    legend_stamps = {kf: s["timestamp"] for kf, s in legend_sections(read_text(LEGENDS_PATH)).items()}
    breakdown_stamps = breakdown_keyframes(read_text(BREAKDOWN_PATH))
    sources = [
        ("KEYFRAME_INDEX section 3", index_stamps),
        ("callout_spec.json", spec_stamps),
        ("CALLOUT_LEGENDS.md", legend_stamps),
        ("BREAKDOWN.md", breakdown_stamps),
    ]
    for label, stamps in sources:
        require(
            sorted(stamps) == sorted(spec_stamps),
            "%s keyframe set differs: %s"
            % (label, sorted(set(spec_stamps) ^ set(stamps))),
        )
    for keyframe in sorted(spec_stamps):
        values = {label: stamps[keyframe] for label, stamps in sources}
        require(
            len(set(values.values())) == 1,
            "%s timestamp mismatch: %s" % (keyframe, values),
        )
    return "%d keyframe timestamps identical across KEYFRAME_INDEX, callout_spec.json, CALLOUT_LEGENDS.md, BREAKDOWN.md" % len(
        spec_stamps
    )


def check_code_taxonomy():
    spec = json.loads(read_text(SPEC_PATH))
    for keyframe, frame in spec["keyframes"].items():
        for callout in frame["callouts"]:
            code = callout["code"]
            require(
                code in TAXONOMY,
                "callout_spec %s callout #%s uses code %s outside the taxonomy"
                % (keyframe, callout["id"], code),
            )
            require(
                callout["category"] == TAXONOMY[code],
                "callout_spec %s callout #%s code %s has category %s instead of %s"
                % (
                    keyframe,
                    callout["id"],
                    code,
                    callout["category"],
                    TAXONOMY[code],
                ),
            )
    for keyframe, section in legend_sections(read_text(LEGENDS_PATH)).items():
        for badge, category, code in section["rows"]:
            require(
                code in TAXONOMY,
                "CALLOUT_LEGENDS %s row %s uses code %s outside the taxonomy"
                % (keyframe, badge, code),
            )
            require(
                category == TAXONOMY[code],
                "CALLOUT_LEGENDS %s row %s code %s has category %s instead of %s"
                % (keyframe, badge, code, category, TAXONOMY[code]),
            )
    documents = {
        "BREAKDOWN.md": read_text(BREAKDOWN_PATH),
        "KEYFRAME_INDEX.md": read_text(KEYFRAME_INDEX_PATH),
        "CALLOUT_LEGENDS.md": read_text(LEGENDS_PATH),
    }
    for label, text in documents.items():
        for token in sorted(set(CODE_TOKEN_RE.findall(text))):
            require(
                token in TAXONOMY,
                "%s references code %s outside V1-V7/UI1-UI5/G1-G5/AU1-AU6"
                % (label, token),
            )
    return "%d taxonomy codes valid, category matches prefix in spec and legend rows" % len(TAXONOMY)


def check_cross_reference_ids():
    text = read_text(BREAKDOWN_PATH)
    rows = 0
    for block in split_sections(text, "### TAT-2 cross-reference")[1:]:
        body = block.split("\n### ", 1)[0]
        for line in body.splitlines():
            line = line.strip()
            if not line.startswith("|"):
                continue
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if len(cells) < 4:
                continue
            if cells[0].startswith("Observed element") or set(cells[0]) <= set("- "):
                continue
            subsystem, status, gap = cells[1], cells[2], cells[3]
            plain_status = status.strip("`")
            numbers = re.findall(r"#(\d+)", subsystem)
            if numbers:
                for number in numbers:
                    require(
                        1 <= int(number) <= 18,
                        "subsystem #%s in row %r is outside 1..18" % (number, cells[0]),
                    )
            else:
                require(
                    "UNCERTAIN" in subsystem,
                    "cross-reference row %r has no subsystem number and no UNCERTAIN marker"
                    % cells[0],
                )
                require(
                    plain_status == "UNVERIFIED_LIVE",
                    "cross-reference row %r has no subsystem number but status %r"
                    % (cells[0], status),
                )
            require(
                PARITY_STATUS_RE.match(plain_status) is not None,
                "parity status %r in row %r is outside the allowed set" % (status, cells[0]),
            )
            status_id = re.search(r"\((PG|HL)-(\d+)\)", plain_status)
            if status_id:
                kind, number = status_id.group(1), int(status_id.group(2))
                require(
                    1 <= number <= (8 if kind == "PG" else 9),
                    "%s-%d in status %r is out of range" % (kind, number, status),
                )
            plain_gap = gap.strip("`")
            if plain_gap != "-":
                gap_match = re.match(r"^(PG|HL)-(\d+)$", plain_gap)
                require(
                    gap_match is not None,
                    "gap cell %r in row %r is neither -, PG-n nor HL-n" % (gap, cells[0]),
                )
                kind, number = gap_match.group(1), int(gap_match.group(2))
                require(
                    1 <= number <= (8 if kind == "PG" else 9),
                    "%s-%d in gap cell %r is out of range" % (kind, number, gap),
                )
                if status_id:
                    require(
                        (kind, number) == (status_id.group(1), int(status_id.group(2))),
                        "status %r disagrees with gap cell %r in row %r" % (status, gap, cells[0]),
                    )
            rows += 1
    require(rows > 0, "no TAT-2 cross-reference rows found in BREAKDOWN.md")
    for label, document in (
        ("BREAKDOWN.md", text),
        ("KEYFRAME_INDEX.md", read_text(KEYFRAME_INDEX_PATH)),
        ("CALLOUT_LEGENDS.md", read_text(LEGENDS_PATH)),
    ):
        for kind, number in re.findall(r"\b(PG|HL)-(\d+)\b", document):
            bound = 8 if kind == "PG" else 9
            require(
                1 <= int(number) <= bound,
                "%s references %s-%s outside 1..%d" % (label, kind, number, bound),
            )
    return "%d cross-reference rows valid, PG 1..8, HL 1..9, subsystem 1..18, parity statuses in allowed set" % rows


def check_determinism():
    names = image_folder_files(ANNOTATED_DIR)
    require(len(names) == 30, "annotated/ holds %d JPEGs instead of 30" % len(names))
    before = {name: sha256_of(ANNOTATED_DIR / name) for name in names}
    stamps = {name: (ANNOTATED_DIR / name).stat().st_mtime_ns for name in names}
    workspace = Path(tempfile.mkdtemp(prefix="verify_baseline_"))
    try:
        replica = workspace / CLIP_DIR.name
        shutil.copytree(CLIP_DIR, replica)
        completed = subprocess.run(
            [sys.executable, str(replica / "tools" / "render_annotations.py")],
            cwd=str(replica),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        require(
            completed.returncode == 0,
            "render_annotations.py failed in the replica (exit %d): %s"
            % (completed.returncode, completed.stdout.strip()[-400:]),
        )
        rendered = replica / "annotated"
        for name in names:
            target = rendered / name
            require(target.is_file(), "replica render produced no %s" % name)
            require(
                sha256_of(target) == before[name],
                "re-rendered %s differs from the committed annotated/ file" % name,
            )
    finally:
        shutil.rmtree(workspace, ignore_errors=True)
    for name in names:
        require(
            sha256_of(ANNOTATED_DIR / name) == before[name],
            "annotated/%s changed during verification" % name,
        )
        require(
            (ANNOTATED_DIR / name).stat().st_mtime_ns == stamps[name],
            "annotated/%s was rewritten during verification" % name,
        )
    return "30/30 re-rendered JPEGs SHA-256 identical to annotated/ (source untouched)"


CHECKS = [
    ("Timeline continuity", check_timeline_continuity),
    ("Template completeness", check_template_completeness),
    ("Image integrity", check_image_integrity),
    ("Callout parity", check_callout_parity),
    ("Timestamp parity", check_timestamp_parity),
    ("Code taxonomy", check_code_taxonomy),
    ("Cross-ref IDs", check_cross_reference_ids),
    ("Determinism", check_determinism),
]


def main():
    failures = 0
    total = len(CHECKS)
    for number, (name, check) in enumerate(CHECKS, start=1):
        try:
            detail = check()
        except CheckFailure as error:
            failures += 1
            print("[FAIL] %d. %s - %s" % (number, name, error))
        except Exception as error:
            failures += 1
            print("[FAIL] %d. %s - %s: %s" % (number, name, type(error).__name__, error))
        else:
            print("[PASS] %d. %s - %s" % (number, name, detail))
    print("%d/%d [%s]" % (total - failures, total, "PASS" if failures == 0 else "FAIL"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
