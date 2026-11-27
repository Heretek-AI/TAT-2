#!/usr/bin/env python3
"""Emit ``mesh_collision.json``: simple-collision primitives from UE dumps.

Inputs
------
Every ``<extracted>/json/**/*.json`` package dump, read-only. Collision is
authored on ``BodySetup`` (StaticMesh, PaperSprite, BrushComponent,
SplineMeshComponent owners) and ``SkeletalBodySetup`` (PhysicsAsset owners)
exports as ``Properties.AggGeom``. The extractor also dumps ``NavCollision``
exports (cooked bulk data only) and, on some BodySetups,
``Properties.CollisionTraceFlag``.

Output
------
``<out-dir>/mesh_collision.json``, schema ``tat2.mesh_collision/1``, one
aggregate file keyed by the owning asset package (``/Game/.../SM_CanA``).
Default out-dir is ``<repo>/game/data/generated``; ``--out-dir`` overrides it.
Keys are sorted, elements stay in source order, floats are never rounded, and
there are no timestamps, so two runs are byte-identical.

JSON contract
-------------
::

    {
      "schema": "tat2.mesh_collision/1",
      "generated_by": "tools/parse_collision.py",
      "source": "extracted/json/**",
      "units": "centimetres, UE asset space (mesh local space)",
      "notes": "FKBoxElem X/Y/Z are HALF-extents; ...",
      "index_data_included": false,
      "counts": {"meshes": 1992, "elements": 8601, "box": 2334,
                 "sphere": 50, "sphyl": 295, "convex": 5922},
      "meshes": {
        "/Game/.../SM_CanA": {
          "owner_type": "StaticMesh",
          "owner_types": ["StaticMesh"],
          "elements": [
            {"type": "box", "center": [0.1385, -0.00038, 13.832],
             "rotation": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
             "half_extent": [15.94, 15.67, 25.46], "rest_offset": 0.0,
             "b_contribute_to_mass": true,
             "collision_enabled": "ECollisionEnabled::QueryAndPhysics",
             "name": "None"},
            {"type": "sphere", "center": [...], "radius": 10.0, ...},
            {"type": "sphyl", "center": [...], "radius": 10.8,
             "length": 7.95, ...},
            {"type": "convex", "index": 0, "vertex_count": 24,
             "vertices_flat": [x, y, z, x, y, z, ...],
             "aabb_min": [...], "aabb_max": [...],
             "aabb_valid": true, "transform": {...}, ...}
          ],
          "collision_profile": "BlockAll",
          "object_type": "ECollisionChannel::ECC_WorldStatic",
          "collision_responses": [{"channel": "Interact",
                                   "response": "ECollisionResponse::ECR_Block"}],
          "body_setup": "BodySetup_0",
          "body_setups": [{"name": "BodySetup_0", "owner_type": "StaticMesh",
                           "owner_object": "StaticMesh'SM_CanA'",
                           "owner_path": "/Game/.../SM_CanA.2",
                           "element_start": 0, "element_count": 1,
                           "default_instance": {...}}],
          "nav_collision": {"present": true, "has_area_data": false,
                            "cooked": [{"format": "NavCollision_Chaos",
                                        "element_count": 410,
                                        "size_on_disk": 410}]}
        }
      }
    }

Grouping and aggregate fields
-----------------------------
``vertices_flat`` is the convex point cloud flattened to ``3 * vertex_count``
floats (``[x, y, z, x, y, z, ...]``). It maps directly to Godot's
``PackedVector3Array`` and preserves the authored ``VertexData`` order; the
nested list shape is deliberately not emitted.

``index_data`` (the authored triangle indices) is opt-in: the default output
omits ``index_data``/``index_count`` because ``ConvexPolygonShape3D.points`` is
a point cloud and does not consume triangles. ``--with-index-data`` emits both
arrays; ``index_data_included`` records which mode produced the file. The two
modes are different byte baselines, so a consumer (or the audit gate) can tell
them apart.

A package may hold several BodySetup exports: 40 of 1992 packages do (a map
package can hold hundreds of BrushComponent / SplineMeshComponent bodies, and a
PhysicsAsset holds one SkeletalBodySetup per bone). Elements from every body
are concatenated in source order and ``body_setups[]`` records the
``element_start``/``element_count`` slice plus the owner and its
``DefaultInstance``. Within one element list the authored order is preserved;
across lists the canonical UE order is used (Box, Sphere, Sphyl, Convex,
TaperedCapsule). ``body_setup`` is emitted only for the single-body case
(the 1952 packages where it is unambiguous). Top-level ``collision_profile``,
``object_type``, ``collision_enabled``, ``collision_responses``,
``collision_trace_flag`` and ``complex_as_simple`` are emitted only when
**every** body in the package carries the value and they all agree; otherwise
they are omitted and the per-body values in ``body_setups[]`` are authoritative.

``complex_as_simple`` is derived from ``CollisionTraceFlag`` (the real field in
this dump; there is no ``bUseComplexAsSimpleCollision`` key on StaticMesh
exports): ``CTF_UseComplexAsSimple`` -> true, ``CTF_UseSimpleAndComplex`` and
``CTF_UseSimpleAsComplex`` -> false. It is omitted when the flag is absent,
rather than assuming a default.

``nav_collision`` is additive: it appears when the package has a ``NavCollision``
export. Every one of the 1977 exports carries only ``CookedFormatData`` (no
``AreaClass``/area list), so ``has_area_data`` is false and only the cooked
format metadata is emitted. 330 packages have NavCollision without any simple
collision and therefore no ``meshes`` entry; ``counts`` records them.

``no_simple_collision`` is the second additive map: one entry per package whose
BodySetup/SkeletalBodySetup exports carry **no** ``AggGeom`` (334 packages in the
shipped dumps). ``kind`` is the consumer contract and is derived only from
authored fields:

* ``complex_as_simple`` - the default trace flag or
  ``CTF_UseComplexAsSimple``; UE collides with the render triangles, so the
  render trimesh is the authored answer (310 packages: 289 no flag, 21
  ``CTF_UseComplexAsSimple``);
* ``no_collision`` - ``DefaultInstance.CollisionEnabled`` is explicitly
  ``NoCollision`` (44), or ``CTF_UseSimpleAsComplex`` leaves nothing simple to
  use (2 of the 9 SimpleAsComplex packages are enabled).

``reason`` names the exact authored trigger (``default_complex_fallback``,
``complex_as_simple_flag``, ``explicit_no_collision``,
``simple_as_complex_without_shapes``). A package that has both an AggGeom body
and a body without one stays authoritative in ``meshes``. The map is separate
from ``counts`` so the measured simple-collision baseline (1992 packages / 8601
elements) stays byte-identical; ``no_simple_collision_counts`` carries its own
census.

Element vocabulary (closed)
---------------------------
``AggGeom`` keys are exactly ``BoxElems``, ``SphereElems``, ``SphylElems``,
``ConvexElems`` and ``TaperedCapsuleElems``; any other key fails the run. Each
element's authored keys are also closed and validated per type, so a new
extractor field fails loudly instead of being dropped. ``TaperedCapsuleElems``
has **0 occurrences** in the shipped dumps; its mapping follows UE's
``FKTAperedCapsuleElem`` (Radius0/Radius1/Length) and is therefore not
exercised by the real-data test, only by the code path itself.

CLI
---
``python3 tools/parse_collision.py [--extracted DIR] [--out-dir DIR]
[--with-index-data] [--quiet]``. Exits non-zero with a message on stderr for an
unreadable/absent dump tree, a malformed BodySetup, an unknown AggGeom key, an
unknown element field or an unknown ``CollisionTraceFlag``.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = "tat2.mesh_collision/1"
GENERATED_BY = "tools/parse_collision.py"
SOURCE = "extracted/json/**"
OUT_NAME = "mesh_collision.json"
UNITS = "centimetres, UE asset space (mesh local space)"
NOTES = (
    "FKBoxElem X/Y/Z are HALF-extents; FKSphereElem Radius; FKSphylElem "
    "Radius+Length as authored; FKConvexElem VertexData is flattened to "
    "vertices_flat in PackedVector3Array order; authored triangle indices are "
    "emitted only with --with-index-data (non-empty on 5919 of 5922 hulls); "
    "no rounding or unit conversion is applied."
)

BODY_TYPES = ("BodySetup", "SkeletalBodySetup")
AGG_KEYS = (
    "BoxElems",
    "SphereElems",
    "SphylElems",
    "ConvexElems",
    "TaperedCapsuleElems",
)
ELEMENT_TYPE = {
    "BoxElems": "box",
    "SphereElems": "sphere",
    "SphylElems": "sphyl",
    "ConvexElems": "convex",
    "TaperedCapsuleElems": "tapered_capsule",
}
ALLOWED_KEYS = {
    "box": {
        "Center",
        "Rotation",
        "X",
        "Y",
        "Z",
        "RestOffset",
        "Name",
        "bContributeToMass",
        "CollisionEnabled",
    },
    "sphere": {
        "Center",
        "Radius",
        "RestOffset",
        "Name",
        "bContributeToMass",
        "CollisionEnabled",
    },
    "sphyl": {
        "Center",
        "Rotation",
        "Radius",
        "Length",
        "RestOffset",
        "Name",
        "bContributeToMass",
        "CollisionEnabled",
    },
    "convex": {
        "VertexData",
        "IndexData",
        "ElemBox",
        "Transform",
        "RestOffset",
        "Name",
        "bContributeToMass",
        "CollisionEnabled",
    },
    "tapered_capsule": {
        "Center",
        "Rotation",
        "Radius0",
        "Radius1",
        "Length",
        "RestOffset",
        "Name",
        "bContributeToMass",
        "CollisionEnabled",
    },
}
REQUIRED_KEYS = {
    "box": {"Center", "Rotation", "X", "Y", "Z"},
    "sphere": {"Center", "Radius"},
    "sphyl": {"Center", "Rotation", "Radius", "Length"},
    "convex": {"VertexData", "IndexData", "ElemBox", "Transform"},
    "tapered_capsule": {"Center", "Rotation", "Radius0", "Radius1", "Length"},
}
TRACE_FLAG_COMPLEX = {
    "ECollisionTraceFlag::CTF_UseComplexAsSimple": True,
    "ECollisionTraceFlag::CTF_UseSimpleAndComplex": False,
    "ECollisionTraceFlag::CTF_UseSimpleAsComplex": False,
}
# Extra properties seen on the owning body export (all optional).
BODY_EXTRA_KEYS = {
    "BoneName": "bone_name",
    "PhysicsType": "physics_type",
    "PhysicalAnimationData": "physical_animation_data",
    "PhysMaterial": "phys_material",
    "bDoubleSidedGeometry": "b_double_sided_geometry",
    "bGenerateMirroredCollision": "b_generate_mirrored_collision",
}


class CollisionError(ValueError):
    """A malformed or unexpected collision dump."""


@dataclass
class Body:
    """One BodySetup / SkeletalBodySetup export."""

    package: str
    owner_type: str
    owner_object: str
    owner_path: str
    name: str
    elements: list[dict[str, Any]] = field(default_factory=list)
    trace_flag: str | None = None
    default_instance: dict[str, Any] | None = None
    extras: dict[str, Any] = field(default_factory=dict)


def _num(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CollisionError(f"{where}: expected number, got {value!r}")
    return float(value)


def _vec3(value: Any, where: str) -> list[float]:
    if not isinstance(value, dict):
        raise CollisionError(f"{where}: expected vector struct, got {value!r}")
    if set(value) != {"X", "Y", "Z"}:
        raise CollisionError(f"{where}: expected X/Y/Z, got {sorted(value)}")
    return [
        _num(value["X"], f"{where}.X"),
        _num(value["Y"], f"{where}.Y"),
        _num(value["Z"], f"{where}.Z"),
    ]


def _rotation(value: Any, where: str) -> dict[str, float]:
    if not isinstance(value, dict):
        raise CollisionError(f"{where}: expected rotator, got {value!r}")
    if set(value) != {"Pitch", "Yaw", "Roll"}:
        raise CollisionError(f"{where}: expected Pitch/Yaw/Roll, got {sorted(value)}")
    return {
        "pitch": _num(value["Pitch"], f"{where}.Pitch"),
        "yaw": _num(value["Yaw"], f"{where}.Yaw"),
        "roll": _num(value["Roll"], f"{where}.Roll"),
    }


def _common(element: dict[str, Any], where: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    if "RestOffset" in element:
        out["rest_offset"] = _num(element["RestOffset"], f"{where}.RestOffset")
    if "bContributeToMass" in element:
        flag = element["bContributeToMass"]
        if not isinstance(flag, bool):
            raise CollisionError(f"{where}.bContributeToMass: expected bool")
        out["b_contribute_to_mass"] = flag
    if "CollisionEnabled" in element:
        out["collision_enabled"] = _str(
            element["CollisionEnabled"], f"{where}.CollisionEnabled"
        )
    if "Name" in element:
        out["name"] = _str(element["Name"], f"{where}.Name")
    return out


def _str(value: Any, where: str) -> str:
    if not isinstance(value, str):
        raise CollisionError(f"{where}: expected string, got {value!r}")
    return value


def _quat(value: Any, where: str) -> dict[str, float]:
    if not isinstance(value, dict):
        raise CollisionError(f"{where}: expected quaternion, got {value!r}")
    missing = {"X", "Y", "Z", "W"} - set(value)
    if missing:
        raise CollisionError(f"{where}: missing quaternion keys {sorted(missing)}")
    return {name: _num(value[name], f"{where}.{name}") for name in ("X", "Y", "Z", "W")}


def _element(
    kind: str, element: Any, index: int, where: str, with_index_data: bool
) -> dict[str, Any]:
    if not isinstance(element, dict):
        raise CollisionError(f"{where}: expected struct, got {element!r}")
    unknown = set(element) - ALLOWED_KEYS[kind]
    if unknown:
        raise CollisionError(f"{where}: unknown element keys {sorted(unknown)}")
    missing = REQUIRED_KEYS[kind] - set(element)
    if missing:
        raise CollisionError(f"{where}: missing element keys {sorted(missing)}")
    out: dict[str, Any] = {"type": kind}
    if kind == "box":
        out["center"] = _vec3(element["Center"], f"{where}.Center")
        out["rotation"] = _rotation(element["Rotation"], f"{where}.Rotation")
        out["half_extent"] = [
            _num(element["X"], f"{where}.X"),
            _num(element["Y"], f"{where}.Y"),
            _num(element["Z"], f"{where}.Z"),
        ]
    elif kind == "sphere":
        out["center"] = _vec3(element["Center"], f"{where}.Center")
        out["radius"] = _num(element["Radius"], f"{where}.Radius")
    elif kind == "sphyl":
        out["center"] = _vec3(element["Center"], f"{where}.Center")
        out["rotation"] = _rotation(element["Rotation"], f"{where}.Rotation")
        out["radius"] = _num(element["Radius"], f"{where}.Radius")
        out["length"] = _num(element["Length"], f"{where}.Length")
    elif kind == "convex":
        vertices_flat: list[float] = []
        for i, vertex in enumerate(element["VertexData"]):
            vertices_flat.extend(_vec3(vertex, f"{where}.VertexData[{i}]"))
        if len(vertices_flat) % 3 != 0:
            raise CollisionError(f"{where}.VertexData: not a multiple of 3")
        indices = element["IndexData"]
        if not isinstance(indices, list) or any(
            isinstance(v, bool) or not isinstance(v, int) for v in indices
        ):
            raise CollisionError(f"{where}.IndexData: expected list of ints")
        box = element["ElemBox"]
        if not isinstance(box, dict) or {"Min", "Max"} - set(box):
            raise CollisionError(f"{where}.ElemBox: expected Min/Max")
        transform = element["Transform"]
        if not isinstance(transform, dict):
            raise CollisionError(f"{where}.Transform: expected struct")
        out["index"] = index
        out["vertex_count"] = len(vertices_flat) // 3
        out["vertices_flat"] = vertices_flat
        if with_index_data:
            out["index_data"] = [int(v) for v in indices]
            out["index_count"] = len(indices)
        out["aabb_min"] = _vec3(box["Min"], f"{where}.ElemBox.Min")
        out["aabb_max"] = _vec3(box["Max"], f"{where}.ElemBox.Max")
        if "IsValid" in box:
            out["aabb_valid"] = bool(box["IsValid"])
        out["transform"] = {
            "rotation": _quat(transform.get("Rotation"), f"{where}.Transform.Rotation"),
            "translation": _vec3(
                transform.get("Translation"), f"{where}.Transform.Translation"
            ),
            "scale3d": _vec3(transform.get("Scale3D"), f"{where}.Transform.Scale3D"),
        }
    else:  # tapered_capsule
        out["center"] = _vec3(element["Center"], f"{where}.Center")
        out["rotation"] = _rotation(element["Rotation"], f"{where}.Rotation")
        out["radius0"] = _num(element["Radius0"], f"{where}.Radius0")
        out["radius1"] = _num(element["Radius1"], f"{where}.Radius1")
        out["length"] = _num(element["Length"], f"{where}.Length")
    out.update(_common(element, where))
    return out


def _body_header(export: dict[str, Any], path: Path) -> tuple[str, str, str, str]:
    """(name, owner_type, owner_object, owner_path) for one body export."""
    outer = export.get("Outer") or {}
    owner_object = _str(outer.get("ObjectName"), f"{path}: Outer.ObjectName")
    owner_path = _str(outer.get("ObjectPath"), f"{path}: Outer.ObjectPath")
    if "'" not in owner_object:
        raise CollisionError(f"{path}: unparsable Outer.ObjectName {owner_object!r}")
    owner_type = owner_object.split("'", 1)[0]
    return (
        _str(export.get("Name", ""), f"{path}: export Name"),
        owner_type,
        owner_object,
        owner_path,
    )


def _body_flags(
    props: dict[str, Any], path: Path
) -> tuple[str | None, dict[str, Any] | None, dict[str, Any]]:
    """(trace_flag, default_instance, extras) for one body export."""
    trace_flag = None
    if "CollisionTraceFlag" in props:
        trace_flag = _str(props["CollisionTraceFlag"], f"{path}: CollisionTraceFlag")
        if trace_flag not in TRACE_FLAG_COMPLEX:
            raise CollisionError(f"{path}: unknown CollisionTraceFlag {trace_flag!r}")
    default_instance = props.get("DefaultInstance")
    if default_instance is not None and not isinstance(default_instance, dict):
        raise CollisionError(f"{path}: DefaultInstance is not a struct")
    extras = {
        target: props[source]
        for source, target in BODY_EXTRA_KEYS.items()
        if source in props
    }
    return trace_flag, default_instance, extras


def _body_without_agg(export: dict[str, Any], package: str, path: Path) -> Body:
    """A BodySetup / SkeletalBodySetup that carries no AggGeom.

    UE has no simple elements here; whether that means "collide with the render
    mesh" or "no collision at all" is decided by the trace flag and the
    DefaultInstance CollisionEnabled, and recorded by `_no_geom_reason()`.
    """
    name, owner_type, owner_object, owner_path = _body_header(export, path)
    trace_flag, default_instance, extras = _body_flags(
        export.get("Properties") or {}, path
    )
    return Body(
        package=package,
        owner_type=owner_type,
        owner_object=owner_object,
        owner_path=owner_path,
        name=name,
        elements=[],
        trace_flag=trace_flag,
        default_instance=default_instance,
        extras=extras,
    )


def _body_export(
    export: dict[str, Any], package: str, path: Path, with_index_data: bool
) -> Body:
    props = export.get("Properties") or {}
    agg = props.get("AggGeom")
    if not isinstance(agg, dict):
        raise CollisionError(f"{path}: {export.get('Name')}: AggGeom is not a struct")
    unknown = set(agg) - set(AGG_KEYS)
    if unknown:
        raise CollisionError(
            f"{path}: {export.get('Name')}: unknown AggGeom keys {sorted(unknown)}"
        )
    elements: list[dict[str, Any]] = []
    for agg_key in AGG_KEYS:
        values = agg.get(agg_key)
        if values is None:
            continue
        if not isinstance(values, list):
            raise CollisionError(
                f"{path}: {export.get('Name')}: {agg_key} is not a list"
            )
        kind = ELEMENT_TYPE[agg_key]
        for index, element in enumerate(values):
            where = f"{path}: {export.get('Name')}.{agg_key}[{index}]"
            elements.append(_element(kind, element, index, where, with_index_data))

    name, owner_type, owner_object, owner_path = _body_header(export, path)
    trace_flag, default_instance, extras = _body_flags(props, path)
    return Body(
        package=package,
        owner_type=owner_type,
        owner_object=owner_object,
        owner_path=owner_path,
        name=name,
        elements=elements,
        trace_flag=trace_flag,
        default_instance=default_instance,
        extras=extras,
    )


def _default_instance_fields(di: dict[str, Any]) -> dict[str, Any]:
    """Snake-case the authored DefaultInstance keys we consume."""
    out: dict[str, Any] = {}
    responses = (di.get("CollisionResponses") or {}).get("ResponseArray")
    if responses is not None:
        if not isinstance(responses, list):
            raise CollisionError("DefaultInstance.CollisionResponses: not a list")
        translated = []
        for response in responses:
            if not isinstance(response, dict):
                raise CollisionError("CollisionResponses entry is not a struct")
            translated.append(
                {
                    "channel": _str(response.get("Channel"), "response.Channel"),
                    "response": _str(response.get("Response"), "response.Response"),
                }
            )
        out["collision_responses"] = translated
    for source, target in (
        ("CollisionProfileName", "collision_profile"),
        ("ObjectType", "object_type"),
        ("CollisionEnabled", "collision_enabled"),
        ("PhysMaterialOverride", "phys_material_override"),
        ("SolverAsyncDeltaTime", "solver_async_delta_time"),
        ("LinearDamping", "linear_damping"),
        ("AngularDamping", "angular_damping"),
        ("MassInKgOverride", "mass_in_kg_override"),
    ):
        if source in di:
            out[target] = di[source]
    if "bAutoWeld" in di:
        out["b_auto_weld"] = di["bAutoWeld"]
    return out


def _uniform(bodies: list[Body], getter) -> tuple[bool, Any]:
    values = [getter(body) for body in bodies]
    if not values:
        return False, None
    first = values[0]
    if any(value is None or value != first for value in values):
        return False, None
    return True, first


def _body_json(body: Body, start: int) -> dict[str, Any]:
    out: dict[str, Any] = {
        "name": body.name,
        "owner_type": body.owner_type,
        "owner_object": body.owner_object,
        "owner_path": body.owner_path,
        "element_start": start,
        "element_count": len(body.elements),
    }
    if body.trace_flag is not None:
        out["collision_trace_flag"] = body.trace_flag
        out["complex_as_simple"] = TRACE_FLAG_COMPLEX[body.trace_flag]
    out.update(body.extras)
    if body.default_instance is not None:
        out["default_instance"] = body.default_instance
        fields = _default_instance_fields(body.default_instance)
        if fields:
            out["default_instance_fields"] = fields
    return out


def _force_simple(body: Body) -> bool | None:
    if body.trace_flag is None:
        return None
    return TRACE_FLAG_COMPLEX[body.trace_flag]


def _profile(body: Body) -> str | None:
    if not body.default_instance:
        return None
    return body.default_instance.get("CollisionProfileName")


def _object_type(body: Body) -> str | None:
    if not body.default_instance:
        return None
    return body.default_instance.get("ObjectType")


def _collision_enabled(body: Body) -> str | None:
    if not body.default_instance:
        return None
    return body.default_instance.get("CollisionEnabled")


def _responses(body: Body) -> list[dict[str, str]] | None:
    if not body.default_instance:
        return None
    return _default_instance_fields(body.default_instance).get("collision_responses")


def _package_json(package: str, bodies: list[Body], nav: dict | None) -> dict:
    elements: list[dict[str, Any]] = []
    body_json: list[dict[str, Any]] = []
    for body in bodies:
        body_json.append(_body_json(body, len(elements)))
        elements.extend(body.elements)

    owner_types = sorted({body.owner_type for body in bodies})
    out: dict[str, Any] = {
        "owner_type": owner_types[0] if len(owner_types) == 1 else "mixed",
        "owner_types": owner_types,
        "elements": elements,
        "body_setups": body_json,
    }
    if len(bodies) == 1:
        out["body_setup"] = bodies[0].name

    ok, profile = _uniform(bodies, _profile)
    if ok:
        out["collision_profile"] = profile
    ok, object_type = _uniform(bodies, _object_type)
    if ok:
        out["object_type"] = object_type
    ok, enabled = _uniform(bodies, _collision_enabled)
    if ok:
        out["collision_enabled"] = enabled
    ok, responses = _uniform(bodies, _responses)
    if ok:
        out["collision_responses"] = responses
    ok, flag = _uniform(bodies, lambda body: body.trace_flag)
    if ok:
        out["collision_trace_flag"] = flag
        out["complex_as_simple"] = TRACE_FLAG_COMPLEX[flag]
    if nav is not None:
        out["nav_collision"] = nav
    return out


def _no_geom_reason(bodies: list[Body]) -> tuple[str, str]:
    """(kind, reason) for a package whose every body has no AggGeom.

    `kind` is the consumer contract:
      * "complex_as_simple" - UE collides with the render triangles, which is
        the authored answer (default trace flag or CTF_UseComplexAsSimple);
      * "no_collision"      - UE collides with nothing (explicit NoCollision, or
        CTF_UseSimpleAsComplex with no simple elements to use).
    """
    enabled = [(body.default_instance or {}).get("CollisionEnabled") for body in bodies]
    flags = [body.trace_flag for body in bodies]
    if enabled and all(value == "ECollisionEnabled::NoCollision" for value in enabled):
        return "no_collision", "explicit_no_collision"
    if flags and all(
        value == "ECollisionTraceFlag::CTF_UseSimpleAsComplex" for value in flags
    ):
        return "no_collision", "simple_as_complex_without_shapes"
    if flags and all(
        value == "ECollisionTraceFlag::CTF_UseComplexAsSimple" for value in flags
    ):
        return "complex_as_simple", "complex_as_simple_flag"
    return "complex_as_simple", "default_complex_fallback"


def _no_simple_json(bodies: list[Body]) -> dict[str, Any]:
    owner_types = sorted({body.owner_type for body in bodies})
    kind, reason = _no_geom_reason(bodies)
    out: dict[str, Any] = {
        "owner_type": owner_types[0] if len(owner_types) == 1 else "mixed",
        "owner_types": owner_types,
        "kind": kind,
        "reason": reason,
        "body_setups": [_body_json(body, 0) for body in bodies],
    }
    if len(bodies) == 1:
        out["body_setup"] = bodies[0].name
    ok, enabled = _uniform(bodies, _collision_enabled)
    if ok:
        out["collision_enabled"] = enabled
    ok, profile = _uniform(bodies, _profile)
    if ok:
        out["collision_profile"] = profile
    ok, flag = _uniform(bodies, lambda body: body.trace_flag)
    if ok:
        out["collision_trace_flag"] = flag
        out["complex_as_simple"] = TRACE_FLAG_COMPLEX[flag]
    return out


def build_payload(root: Path, with_index_data: bool = False) -> dict[str, Any]:
    if not root.is_dir():
        raise CollisionError(f"missing extracted json directory {root}")
    files = sorted(root.rglob("*.json"))
    if not files:
        raise CollisionError(f"no *.json dumps under {root}")

    bodies: dict[str, list[Body]] = defaultdict(list)
    bodies_no_geom: dict[str, list[Body]] = defaultdict(list)
    nav_by_package: dict[str, dict[str, Any]] = {}
    kind_counts: Counter[str] = Counter()
    elem_counts: Counter[str] = Counter()
    element_totals: dict[str, int] = defaultdict(int)
    empty_bodies = 0
    non_package_documents = 0
    nav_with_area = 0

    for path in files:
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise CollisionError(f"{path}: {exc}") from exc
        if not isinstance(document, list):
            non_package_documents += 1
            continue
        for export in document:
            if not isinstance(export, dict):
                continue
            kind = export.get("Type")
            props = export.get("Properties") or {}
            if kind == "NavCollision":
                outer = export.get("Outer") or {}
                owner_path = outer.get("ObjectPath")
                if not isinstance(owner_path, str) or "." not in owner_path:
                    raise CollisionError(f"{path}: NavCollision without owner path")
                package = owner_path.rsplit(".", 1)[0]
                cooked = []
                for name, data in (export.get("CookedFormatData") or {}).items():
                    if not isinstance(data, dict):
                        raise CollisionError(f"{path}: cooked nav data is not a struct")
                    cooked.append(
                        {
                            "format": name,
                            "element_count": data.get("ElementCount"),
                            "size_on_disk": data.get("SizeOnDisk"),
                        }
                    )
                has_area = bool(props)
                if has_area:
                    nav_with_area += 1
                nav_by_package[package] = {
                    "present": True,
                    "has_area_data": has_area,
                    "cooked": sorted(cooked, key=lambda item: item["format"]),
                }
                continue
            if kind not in BODY_TYPES:
                continue
            outer = export.get("Outer") or {}
            owner_path = outer.get("ObjectPath")
            if not isinstance(owner_path, str) or "." not in owner_path:
                raise CollisionError(
                    f"{path}: {kind} {export.get('Name')!r} has no package path"
                )
            package = owner_path.rsplit(".", 1)[0]
            if "AggGeom" not in props:
                # A BodySetup with no AggGeom has no authored simple elements.
                # UE then either falls back to the render triangles (default /
                # CTF_UseComplexAsSimple) or has no collision at all (explicit
                # NoCollision, or CTF_UseSimpleAsComplex with nothing simple to
                # use). Recorded separately so the consumer can tell the two
                # apart instead of inventing a trimesh for both.
                bodies_no_geom[package].append(_body_without_agg(export, package, path))
                continue
            body = _body_export(export, package, path, with_index_data)
            bodies[package].append(body)
            kind_counts[kind] += 1
            count = len(body.elements)
            elem_counts[kind] += count
            for element in body.elements:
                element_totals[element["type"]] += 1
            if count == 0:
                empty_bodies += 1

    meshes = {
        package: _package_json(package, bodies[package], nav_by_package.get(package))
        for package in sorted(bodies)
    }
    nav_only = sorted(set(nav_by_package) - set(bodies))
    # BodySetups with no AggGeom. A package that also has authored simple
    # elements stays authoritative in `meshes`; this map only informs the
    # consumer about packages that would otherwise look like "no record".
    no_simple = {
        package: _no_simple_json(bodies_no_geom[package])
        for package in sorted(bodies_no_geom)
    }
    no_simple_kinds = Counter(entry["kind"] for entry in no_simple.values())

    counts: dict[str, Any] = {
        "meshes": len(meshes),
        "body_setups": kind_counts["BodySetup"],
        "skeletal_body_setups": kind_counts["SkeletalBodySetup"],
        "elements": sum(element_totals.values()),
        "box": element_totals["box"],
        "sphere": element_totals["sphere"],
        "sphyl": element_totals["sphyl"],
        "convex": element_totals["convex"],
        "tapered_capsule": element_totals["tapered_capsule"],
        "body_setup_elements": elem_counts["BodySetup"],
        "skeletal_body_setup_elements": elem_counts["SkeletalBodySetup"],
        "empty_body_setup": empty_bodies,
        "multi_body_setup_packages": sum(
            1 for package_bodies in bodies.values() if len(package_bodies) > 1
        ),
        "packages_with_uniform_collision_profile": sum(
            1
            for package_bodies in bodies.values()
            if _uniform(package_bodies, _profile)[0]
        ),
        "packages_complex_as_simple": sum(
            1
            for package_bodies in bodies.values()
            if _uniform(package_bodies, _force_simple) == (True, True)
        ),
        "nav_collision_packages": len(nav_by_package),
        "nav_collision_packages_with_area_data": nav_with_area,
        "nav_collision_packages_without_simple_collision": len(nav_only),
        "files_scanned": len(files),
        "non_package_documents": non_package_documents,
    }
    return {
        "schema": SCHEMA,
        "generated_by": GENERATED_BY,
        "source": SOURCE,
        "units": UNITS,
        "notes": NOTES,
        "index_data_included": with_index_data,
        "counts": counts,
        # Additive census (not part of `counts`, which is the simple-collision
        # baseline pinned by tools/test_parse_collision.py).
        "no_simple_collision_counts": {
            "packages": len(no_simple),
            "complex_as_simple": no_simple_kinds["complex_as_simple"],
            "no_collision": no_simple_kinds["no_collision"],
        },
        "meshes": meshes,
        "no_simple_collision": no_simple,
    }


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit mesh_collision.json from UE package dumps."
    )
    parser.add_argument(
        "--extracted",
        type=Path,
        default=ROOT / "extracted",
        help="extracted tree root (default: <repo>/extracted)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "game" / "data" / "generated",
        help="output directory (default: <repo>/game/data/generated)",
    )
    parser.add_argument(
        "--with-index-data",
        action="store_true",
        help="also emit convex index_data/index_count (default: omit triangles)",
    )
    parser.add_argument("--quiet", action="store_true", help="no stdout summary")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    root = args.extracted / "json"
    try:
        payload = build_payload(root, with_index_data=args.with_index_data)
    except CollisionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    out = args.out_dir / OUT_NAME
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except OSError as exc:
        print(f"error: cannot write {out}: {exc}", file=sys.stderr)
        return 1
    if not args.quiet:
        counts = payload["counts"]
        mode = "with index data" if args.with_index_data else "point cloud only"
        print(
            f"wrote {out} ({counts['meshes']} packages, "
            f"{counts['elements']} elements: {counts['box']} box, "
            f"{counts['sphere']} sphere, {counts['sphyl']} sphyl, "
            f"{counts['convex']} convex; {mode})"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
