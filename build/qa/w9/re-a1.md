# W9-P1 / A1 — authored UE `AggGeom` → Godot collision: binding answers + evidence

Read-only research lane. Worktree `/home/john/Projects/TAT-2-rem-w9-p1`, HEAD `c2a1cd8`.
**No Godot process was run.** Every number below was recomputed here with `python3` from
`extracted/json/**` and `game/data/generated/mesh_collision.json`
(sha256 `deb3771e…c8e6`, 17,626,566 bytes, mtime 2026-11-25 04:48 — same file the lead's
`facts-a1.md` measured), plus GLB accessor `min`/`max` read with `struct`/`json`.
Tags: **[A]** authored UE data/doc, **[M]** measured here, **[I]** inference (reasoned, not measured).

---

## 0. Binding answers

| # | Question | Binding answer | Status |
|---|---|---|---|
| B1 | Element-local space & units | **Mesh-local UE space, centimetres, verbatim, no rounding.** `center`/`half_extent`/`radius`/`length`/`vertices_flat`/`transform.translation` are all the raw `FK*Elem` floats (`tools/parse_collision.py:337-352` box/sphyl/sphere, `:353-386` convex, `:144` `UNITS`). Multiply by **0.01** for Godot metres. | [A] dump fields + [M] 493-hull AABB match (0.38 % median) |
| B2 | Rotation | `box`/`sphyl` carry `rotation{pitch,roll,yaw}` = UE `FRotator` **degrees**; `sphere` has none; `convex` carries a UE `FTransform` `{rotation{X,Y,Z,W}, translation(cm), scale3d}` (`:280-289`, `:380-386`). Godot basis = **`P · R · P`** (swap rows+cols 1↔2, = `parse_tables.ue_mat4_to_godot_trs`), origin = `P(center) * 0.01`. Convex: **apply scale3d ⊙ v → quaternion → + translation in UE space, then convert** (bake into the points; 41/5,922 hulls non-identity, 37 of them across 25 paths / 713 Guildhall instances). | [A]+[M] rotator fit test: 6.5 % vs 61 % transposed |
| B3a | Box axis/units | `BoxShape3D.size = Vector3(X, Z, Y) * 0.01`. **`X`/`Y`/`Z` are FULL extents, not half-extents.** The producer's field name `half_extent` and its `NOTES` (“FKBoxElem X/Y/Z are HALF-extents”, `:146-147`) are **wrong by 2×**. | [A] UE docs+CARLA + [M] 453 meshes, median ratio 1.9997 |
| B3b | Sphere | `SphereShape3D.radius = Radius * 0.01`. | [A] `/Engine/BasicShapes/Sphere` 50 → 0.5 m |
| B3c | Capsule | `CapsuleShape3D.radius = Radius * 0.01`; `CapsuleShape3D.height = (Length + 2*Radius) * 0.01`. UE `Length` is the **cylindrical segment only** (“add Radius to both ends to find total length”); Godot `height` includes both caps → they are **equal** with that formula. UE capsule axis = **local Z** → after the Y/Z swap it is Godot **local Y**, i.e. `CapsuleShape3D`'s default axis, so the same `P·R·P` basis needs no extra ±90°. | [A] UE API docs; [M] 17/57 hulls with L<2R |
| B3d | Convex | `ConvexPolygonShape3D.points[i] = P( T(vertices_flat[3i..3i+2]) )` — flat x,y,z cm triplets, `T` = the element transform; shape transform identity (bake). | [A]+[M] 493/493 |
| B4 | Empirical cross-check | Boxes: `X / mesh_size = 0.9999` median (n=30, 12 exact). Capsules: 23/25 rotation-0 single-sphyl meshes have the mesh's **longest AABB axis on UE Z**, and the two that don't are near-spherical or rotated (the rotated ones move the axis exactly as `roll=90→Y`, `pitch=90→X` predicts). `(L+2R)/mesh_height = 1.017` median (12 ≈ fit-to-mesh). | [M] §4 |
| B5 | Collision enable | Mesh-level uniform `collision_enabled`: **31 `NoCollision`, 7 `QueryOnly`, 1,954 absent (= `QueryAndPhysics` default)**. Element-level: 8,599 `QueryAndPhysics`, 2 `PhysicsOnly` (both on a `PhysicsAsset`, never a static mesh). Guildhall load set: **12 paths / 337 instances `NoCollision`**, **7 paths / 158 instances `QueryOnly`**. `NoCollision` → emit **no shape**. `QueryOnly` → keep the shape but **not on a layer any mover's mask includes** (Godot has no per-shape query-only flag): dedicated layer + added to the LOS/query masks, or an `Area3D`. | [A] counts + [I] Godot encoding |
| B6 | 107 meshes with no record | 94/107 have a `BodySetup` export with **no `AggGeom` property at all** and `CollisionProfileName = BlockAll` (+ `NavCollision`); 13/107 have **no dump file at all** (Graybox `GB_*`, `SM_Shape_*`). UE default (`CTF_UseDefaultCollision`) with no simple collision = **complex-as-simple**, so a `ConcavePolygonShape3D` from the render mesh **is the authored answer, not a port invention** — for the 94. For the 13 there is no authored data either way. | [A] dump + [A] UE default rule |
| B7 | Multi-body-setup meshes | **Never merge.** All **1,647/1,647** `StaticMesh` packages have exactly **one** `body_setups[]` entry; `body_setup` names it. The 40 multi-body packages are **map packages** (19 `PhysicsAsset`-only, 13 `BrushComponent`-only, 5 mixed Brush+Spline, 3 `SplineMeshComponent`-only; max 211 bodies, `OldManor_Geo`). A `UStaticMesh` has one `BodySetup`; the other bodies are different scene objects. | [A] producer + [M] counts |
| B8 | Projected shape cost (15-file Guildhall) | 24,254 deduped instances on paths with data, **38,831 elements** (box 22,721 / convex 14,906 / sphyl 826 / sphere 378). **(a) one shape per element = 38,831** (blows `MAX_TOTAL_SHAPES = 32000`, `run_tests.gd:501`). **(b) coalesce all-primitive meshes = 30,724** (15,818 + 14,906) — under 32,000 but **above `MAX_BUILDING_SHAPES = 28000`** (`level_loader.gd:191`). Coalescing is mandatory, and headroom is ≈1.2 k shapes. | [M] |

### The conversion, in one block (drop-in)

```python
S = [[1,0,0],[0,0,1],[0,1,0]]                 # UE -> Godot mesh space: y<->z swap, NO sign flip
def P(v):   return Vector3(v[0], v[2], v[1]) * 0.01          # cm -> m
def PMP(M): return [[M[i][j] for j in (0,2,1)] for i in (0,2,1)]   # == parse_tables.ue_mat4_to_godot_trs

# box  (X,Y,Z are FULL extents, cm)
shape = BoxShape3D.new(); shape.size = Vector3(X, Z, Y) * 0.01
xform = Transform3D(Basis(PMP(ue_rotator_to_mat3(rotation))), P(center))
# sphere
shape = SphereShape3D.new(); shape.radius = Radius * 0.01
xform = Transform3D(Basis(), P(center))
# sphyl (UE Length excludes the caps; Godot height includes them)
shape = CapsuleShape3D.new(); shape.radius = Radius * 0.01
shape.height = (Length + 2.0 * Radius) * 0.01
xform = Transform3D(Basis(PMP(ue_rotator_to_mat3(rotation))), P(center))   # Z axis -> Godot Y
# convex (bake the element FTransform, then convert)
pts = [P(quat_rot(rotation) * (Vector3(sx,sy,sz) * v) + translation) for v in vertices_flat]
shape = ConvexPolygonShape3D.new(); shape.points = PackedVector3Array(pts)
xform = Transform3D(Basis(), Vector3.ZERO)
```

`ue_rotator_to_mat3` = `tools/parse_tables.py:55-77` **verbatim** (it is the UE
`FRotationMatrix` in column-vector form, with the documented negated `m12`). `PMP` is the same
row/column 1↔2 swap that `ue_mat4_to_godot_trs` (`tools/parse_tables.py:96-99`) applies to
instance transforms, so element and instance bases compose without a second convention.
The level-JSON `basis` array is **row-major** (`parse_tables.py:141-151` emits
`[c0.x, c1.x, c2.x, c0.y, …]`), so reconstruct with
`Basis(Vector3(b0,b3,b6), Vector3(b1,b4,b7), Vector3(b2,b5,b8))` — exactly what
`level_loader.gd:6537` (`_dict_to_transform`) does. (Note: `_spawn_level_niagara`,
`level_loader.gd:5964-5970`, uses the *transposed* reading. Not collision, not investigated.)

---

## 1. Element-local space and units — **mesh-local, centimetres** [A]+[M]

Producer path: `_body_export()` reads `export.Properties.AggGeom` (`tools/parse_collision.py:400-421`),
`_element()` maps dump field names to JSON names:

| JSON field | dump key | producer line | units |
|---|---|---|---|
| `center` | `Center` `{X,Y,Z}` | `338`, `346`, `349`, `388` via `_vec3` `268-277` | cm, mesh-local |
| `half_extent` | `X`,`Y`,`Z` | `340-344` via `_num` `262-265` | cm — **FULL extents** (see §3.1) |
| `radius` | `Radius` | `347`, `351`, `390-391` | cm |
| `length` | `Length` | `352`, `392` | cm (cylinder segment, §3.3) |
| `vertices_flat` | `VertexData[i].{X,Y,Z}` | `354-358`, flattened `372` | cm, mesh-local, pre-element-transform |
| `transform.translation` | `Transform.Translation` | `382-384` | cm |
| `transform.rotation` | `Transform.Rotation.{X,Y,Z,W}` | `381` via `_quat` `316-322` | quaternion |
| `transform.scale3d` | `Transform.Scale3D` | `385` | unitless |
| `aabb_min/max` | `ElemBox.Min/Max` | `376-377` | cm, **pre-element-transform** (§2.3) |

The announced contract is `units: "centimetres, UE asset space (mesh local space)"` (`:144`) and
`notes: "… no rounding or unit conversion is applied"` (`:145-151`). Field names are closed
(`ALLOWED_KEYS` `:168-219`, `REQUIRED_KEYS` `:220-226`) and unknown keys fail the run, so nothing is
silently dropped.

### 1.1 Independent verification against the render mesh

* **`/Engine/BasicShapes/Cube`** — `BodySetup.BoxElems[0]` = `X=Y=Z=100.0`,
  `Center=(0,0,0)` (`extracted/json/Engine/Content/BasicShapes/Cube.json`); the same dump's
  `StaticMesh.ExtendedBounds.BoxExtent = {50,50,50}` and the GLB AABB is `±0.5 m`.
  So **`X=100` ⇔ a 1 m cube** — the values are cm and they are *full* extents.
  (The lane brief expected “half_extent 100 → a 2 m cube”; the GLB, the authored `ExtendedBounds`
  and the authored box all say 1 m. See §3.1.)
* **`/Engine/BasicShapes/Sphere`** — `Radius = 50.000004`, GLB AABB `±0.5 m` → radius is a true
  radius in cm. **`/Engine/BasicShapes/Plane`** — `X=Y=100, Z=0`, GLB `±0.5 m` in X/Z and flat in Y.
* **`SM_Civic_DoorwayD_Int_6x8`** (7 convex hulls, translations up to 450 cm): union of
  `Transform(VertexData)` = `x[-600,0] y[0,45.5] z[-1,850]` cm; the GLB (mapped back to UE axes)
  = `x[-600,0] y[0,47.5] z[-0.9,850]` cm. Exact — units, mesh-local space and the element
  translation all confirmed at once.
* **All 493 single-convex placed meshes with a GLB**: median deviation between the hull AABB (after
  applying the element transform) and the mesh AABB = **0.38 %** of the largest mesh extent
  (383/493 within 2 %, 453/493 within 10 %) — the hulls are fitted to the mesh, in mesh-local cm.
* **`SM_Urban_Ext_Wall_4x6`** box `center = (-199.971, 15.013, 325.000)` equals the mesh's own
  AABB centre in UE coordinates (`x[-400, 0.06] y[0, 30] z[0, 650]`).

**[I]** Nothing in the pipeline rescales: the GLB exporter divides by exactly 100 on every mesh
checked (pillar 1201→12.002 m, wall 650→6.5 m, sphere 50→0.5 m), so cm→m is a clean `*0.01`.

---

## 2. Rotation [A]+[M]

### 2.1 What each element carries

| type | rotation representation | dump (`extracted/json/**`) | producer |
|---|---|---|---|
| `box` | `FRotator{pitch,yaw,roll}` deg | `Rotation.{Pitch,Yaw,Roll}` | `_rotation` `:280-289` → JSON `rotation{pitch,yaw,roll}` (`:339`) |
| `sphyl` | `FRotator` | same | `:350` |
| `tapered_capsule` | `FRotator` | 0 occurrences | `:389` |
| `sphere` | **none** | — | `:345-347` |
| `convex` | `FTransform` | `Transform.{Rotation{X,Y,Z,W}, Translation{X,Y,Z}, Scale3D{X,Y,Z}}` | `:380-386` |

Raw confirmation (`SM_PillarBasementA_12m.json`, `SM_CanA.json`): `"Rotation": {"Pitch":0.0,"Yaw":0.0,"Roll":0.0}`
and `"Transform": {...}` keys exactly as above. In the whole file 635/2,334 boxes and 41/5,922
convex hulls carry a non-identity transform (37 hulls across 25 paths / 713 instances in the
Guildhall load set: translation 26, scale 19, rotation 2).

### 2.2 The exact mapping, and why it is `P·R·P`

The imported mesh lives in **glTF space** (Godot's importer does not re-orient glTF; the GLB root
node here is `{"mesh": 0}` with no transform). The GLB is written with the **Y/Z swap and no sign
flip**, which is measurable on asymmetric authored bounds:

```
SM_Civic_GuildhallOfficeFloor: UE y[-260.2, 128.2] cm  ->  GLB z[-2.6018, 1.2822] m   (sign kept)
                               UE z[0, 50]         cm  ->  GLB y[0.0000, 0.5000] m
```

So the mesh-space map is `S = [[1,0,0],[0,0,1],[0,1,0]]`, `p_g = S·p_ue·0.01` (note `det S = −1`:
this is the left-handed UE frame expressed in the right-handed Godot frame; it is the *same*
mirror the render mesh got, which is why collision must use the identical map and must not
“fix” it by negating an axis).

A UE rotation `R` therefore becomes `R_g = S·R·S⁻¹ = S·R·S`, which is precisely the row/column
1↔2 swap `ue_mat4_to_godot_trs` performs, and whose translation line is
`p = [m[0][3]*0.01, m[2][3]*0.01, m[1][3]*0.01]` (`tools/parse_tables.py:98`). Consequence:
`Basis = PMP(ue_rotator_to_mat3(rotation))`, `origin = P(center)*0.01`, and no separate ±90°
correction for capsules (UE's Z axis lands on Godot's Y, `CapsuleShape3D`'s own axis).

### 2.3 Measuring the rotator convention (it is not a guess)

19 meshes have exactly one **rotated** box and a GLB. For each, project every mesh vertex onto the
three authored box axes and compare `max|projection|` with the authored extent:

| candidate rotation | mean \|err\| | median | p90 |
|---|---|---|---|
| **`ue_rotator_to_mat3` (repo)** | **0.178** | **0.065** | 0.457 |
| transposed (= inverse) | 0.755 | 0.609 | 1.210 |
| identity (control) | 0.695 | 0.362 | 1.805 |

6.5 % median is a fitted-box fit; the alternatives are ~10× worse. Same test end-to-end in
**Godot** space (shape corners from the final formula vs the GLB AABB): median centre error
**0.000 m** / size error **0.000 m** for 14 unrotated boxes, and 0.008 m / 0.038 m for 14 rotated
boxes (residual = the box is a hand fit, not the mesh).

Worked example (`/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6`, rot 0):
authored `center (−199.971, 15.013, 325.000)` cm, `X,Y,Z = (400.058, 30.032, 650.000)` cm →
`origin (−1.9997, 3.25, 0.1501)`, `size (4.0006, 6.5, 0.3003)`, basis identity;
GLB AABB `(−4.0, 0, 0) … (0.001, 6.5, 0.3)` → identical.

### 2.4 Convex `Transform` must be applied by the consumer

* `ElemBox` (`aabb_min/max`) equals the AABB of the **raw** `vertices_flat` in **41/41**
  non-identity-transform hulls (max coordinate difference 0.00 cm), and the AABB of
  `T(vertices)` in **0/41** (deviations up to 450 cm). **`ElemBox` is a pre-transform cache —
  never use it as the hull's bound, and never as a fast path when `transform` ≠ identity.**
* `scale3d` is non-unit on 22 hulls in the file (19 in the load set) — it must be applied, in the
  element's local axes, before the quaternion.
* Order matters: `v' = R_q · (scale3d ⊙ v) + translation`, in **UE space**, then `P(·)*0.01`.
  Verifying that order on the doorway reproduces the mesh exactly (§1.1).

---

## 3. Axis conventions per element type

### 3.1 Box — `X`,`Y`,`Z` are **full extents** (the producer's label is wrong) [A]+[M]

Godot: `size = Vector3(X, Z, Y) * 0.01`.

Evidence, in increasing strength:

1. **The engine's own cube**: authored `X=Y=Z=100.0`, authored `ExtendedBounds.BoxExtent = 50`,
   GLB `±0.5 m`. A 100 cm full extent for a 1 m cube.
2. **UE API docs** (`unreal.KBoxElem`, `PhysicsEngine/BoxElem.h`): `x` = “**Extent of the box along
   the x-axis**”. UE's other “extent” fields (`FBoxSphereBounds.BoxExtent`) are half-sizes, so the
   doc string alone is ambiguous — hence (3) and (4).
3. **CARLA's UE exporter**, real shipped code:
   `FVector HalfExtent(box.X / 2.0f, box.Y / 2.0f, box.Z / 2.0f);` — it divides by two to get the
   half extent.
4. **Measured over the tree**: 453 axis-aligned single-box meshes; ratio `2·X / mesh_size` has
   median **1.99968**, 280 meshes sit at 2.0 ±5 % on **all three axes**, **zero** at 1.0.
   Reading `X` as a half-extent would mean every artist authored collision at exactly twice the
   visual size in all three axes — impossible; reading it as a full extent means the box equals
   the mesh (`X/mesh = 0.9999` median over the 30 high-instance Guildhall meshes, §4).
5. Individual axes deviate only where the artist meant to (e.g. `SM_Civic_WallA_Int_4x8`
   `X/Z = 1.000/1.001` (4 m × 8 m wall) and `Y = 0.475` — the box covers the 25 cm structural core
   of a 52 cm wall with trim). Under the half-extent reading that wall would be 16 m tall.

> **Action for the lead:** `tools/parse_collision.py:340-344` names this field `half_extent`, and
> `:146-147` asserts “FKBoxElem X/Y/Z are HALF-extents”. Both are wrong by 2×. A consumer written to
> the documented note (`size = 2 * half_extent * 0.01`) would make **every box twice its authored
> size** — the single highest-impact trap in this dataset. Fix the producer's name/notes in a
> follow-up (not this lane); until then, consumers must divide by nothing.

Also: one placed box has a zero extent — `/Engine/BasicShapes/Plane` `X,Y,Z=(100,100,0)`, 6
instances. `BoxShape3D` with a 0 axis is degenerate in Jolt; clamp (the current loader uses
`maxf(sz, 0.1)`, `level_loader.gd:1895`).

### 3.2 Sphere

`radius = Radius * 0.01`; position `P(center)*0.01`; no rotation. Verified against
`/Engine/BasicShapes/Sphere` (`50.000004` → `±0.5 m`). 13 such elements on 13 Guildhall paths
(378 instance-elements).

### 3.3 Capsule (`sphyl`) — `Length` excludes the caps; UE axis is Z [A]

UE 5.7 API, `PhysicsEngine/SphylElem.h` (`dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/FKSphylElem`):

* Struct summary: “Capsule shape used for collision. **Z axis is capsule axis.**”
* `Length` — “**This is of line-segment ie. add Radius to both ends to find total length.**”
* `Radius` — “Radius of the capsule”; `Center` — “Position of the capsule's origin”.
* Functions: `GetScaledCylinderLength` — “Returns the scaled length of the cylinder part of the Sphyl”;
  `GetScaledHalfLength` — “Returns half of the total scaled length of the Sphyl, **which includes the
  scaled top and bottom caps**”. (Same wording for `KTaperedCapsuleElem`: “Length of line-segment.
  Add Radius0 and Radius1 to find total length.”)

Therefore **total capsule length = `Length + 2·Radius`**, which is exactly Godot's
`CapsuleShape3D.height` (caps included) → `height = (Length + 2*Radius) * 0.01`, `radius = Radius*0.01`,
no extra rotation (UE Z → Godot Y under `P·R·P`).

Corroboration in the shipped data:

* **17 of 57** Guildhall-load-set sphyls have `Length < 2·Radius` (min `Length` 0.066 cm with
  `Radius` 144.68). That is legal only if `Length` is the cylinder segment; if `Length` were the
  total it would be a degenerate capsule.
* 23/25 rotation-0 single-sphyl meshes have the mesh's **longest AABB axis on Z** (§4 table);
  `SM_BushB` (a near-spherical bush capsule) is the sole exception.
* Rotated capsules move the axis exactly as the matriarch predicts: `roll=90` → long axis Y
  (`SM_ClimbPipeStraight_3m`, centre offset `y=−150` for a 290 cm capsule), `pitch=90` → long axis X
  (`SM_CablingB`, `SM_LightLrgA`).
* Median `(L+2R)/mesh_height = 1.017` over the 30 sampled capsules; 12 of them are within ±5 % of
  the mesh height, i.e. the “fit to mesh” authoring pattern is `L + 2R = H`. (The 3 pillars are
  inverted: `L/H = 0.965–1.000`, e.g. `SM_Civic_Pillar_6` `L=600.0` = its 600 cm height — the
  artist typed the height into `Length`. That is the authoring error the docs-vs-data distinction
  exposes: the faithful capsule for that pillar is 698.8 cm tall.)

Worked example `SM_PillarBasementA_12m`: `Radius 66.2977`, `Length 1186.7773` →
`radius 0.6630 m`, `height 13.1937 m`, basis identity (capsule axis Godot Y), origin
`(0, 6.000, 0)`.

### 3.4 Convex

`points` = flat `x,y,z` triplets, cm, mesh-local, **plus** the element `FTransform` (§2.4), then
`(x, z, y) * 0.01`. 918 elements on the 889 placed paths; 4 ≤ `vertex_count` ≤ 153; no empty or
invalid hulls in the load set. `index_data` is absent by default (`index_data_included: false`) and
is not needed — `ConvexPolygonShape3D.points` is a point cloud.

---

## 4. Empirical cross-check (the mandated 30 + 30)

Script: `/tmp/w9a1_common.py` + inline harness (stdlib only; GLB JSON chunk via `struct`/`json`,
`accessors[POSITION].min/max`), mapping GLB → UE space with the measured swap `(x, y, z)_glb =
(X, Z, Y)_ue / 100`.

### 4.1 Single-`sphyl` meshes (all 25 in the Guildhall load set + 5 more from the file)

| mesh | inst | R | L | L+2R | mesh ext UE (x,y,z) | longest | cap axis Z? | (L+2R)/H | L/H |
|---|---:|---:|---:|---:|---|---|---|---:|---:|
| SM_PillarBasementA_12m | 26 | 66.3 | 1186.8 | 1319.4 | 134,135,1200 | Z | ✓ | 1.099 | 0.989 |
| SM_PillarBasementA_6m | 16 | 66.3 | 586.8 | 719.3 | 133,133,608 | Z | ✓ | 1.183 | 0.965 |
| SM_Civic_Pillar_6 | 2 | 49.4 | 600.0 | 698.8 | 80,80,600 | Z | ✓ | 1.165 | 1.000 |
| SM_CandleA | 69 | 7.7 | 7.2 | 22.7 | 14,15,19 | Z | ✓ | 1.206 | 0.384 |
| SM_CandelabraFloorA | 3 | 10.0 | 160.0 | 180.0 | 61,62,173 | Z | ✓ | 1.042 | 0.926 |
| SM_LightSm_PostA_Tall | 7 | 12.1 | 323.2 | 347.4 | 51,50,349 | Z | ✓ | 0.997 | 0.927 |
| SM_LightSm_SconceA | 24 | 18.3 | 10.2 | 46.8 | 24,28,30 | Z | ✓ | 1.575 | 0.344 |
| SM_LightLrgA | 22 | 23.7 | 0.1 | 47.5 | 73,73,70 | X | (rot pitch 90) | 0.652 | 0.001 |
| SM_LightLrgB | 11 | 26.5 | 55.1 | 108.2 | 53,53,101 | Z | ✓ | 1.069 | 0.545 |
| SM_LightLrgC | 8 | 33.6 | 17.5 | 84.8 | 67,67,83 | Z | ✓ | 1.019 | 0.210 |
| SM_LightSmB_Brass | 46 | 15.4 | 9.2 | 39.9 | 29,29,39 | Z | ✓ | 1.015 | 0.233 |
| SM_LightSmC_Brass | 7 | 17.4 | 25.4 | 60.3 | 32,32,57 | Z | ✓ | 1.056 | 0.446 |
| SM_LightSmC_Iron | 40 | 17.4 | 25.4 | 60.3 | 32,32,57 | Z | ✓ | 1.056 | 0.446 |
| SM_LightSmD | 11 | 30.6 | 4.9 | 66.1 | 38,38,33 | X | (rot roll 90) | 1.721 | 0.127 |
| SM_LanternGuardA | 4 | 10.1 | 26.9 | 47.1 | 25,24,50 | Z | ✓ | 0.938 | 0.537 |
| SM_CandelabraTableA | 4 | 6.0 | 37.3 | 49.4 | 33,33,50 | Z | ✓ | 0.984 | 0.743 |
| SM_BushB | 1 | 144.7 | 143.5 | 432.9 | 402,256,346 | X | ✗ (near-sphere) | 1.078 | 0.357 |
| SM_sf2_birch_02 | 1 | 12.5 | 1062.1 | 1087.2 | 565,626,1149 | Z | ✓ | 0.946 | 0.924 |
| SM_sf2_birch_07 | 2 | 26.6 | 2482.8 | 2536.1 | 897,1060,2876 | Z | (tilted) | 0.882 | 0.863 |
| SM_sf2_birch_smallA | 2 | 8.0 | 464.9 | 481.0 | 359,384,647 | Z | ✓ | 0.744 | 0.719 |
| SM_ClayJarPaintD1 | 21 | 15.9 | 37.9 | 69.7 | 32,32,63 | Z | ✓ | 1.113 | 0.606 |
| SM_MetalPipeModuleF | 10 | 12.3 | 277.4 | 301.9 | 28,301,52 | Y | (rot roll 90) | 1.002 | 0.921 |
| SM_StreetSignageA | 5 | 31.8 | 468.0 | 531.6 | 64,64,535 | Z | ✓ | 0.993 | 0.874 |
| SM_CablingB | 136 | 4.9 | 29.3 | 39.1 | 36,9,10 | X | (rot pitch 90) | 1.082 | 0.811 |
| SM_Electrotype | 2 | 30.1 | 67.4 | 127.7 | 75,86,114 | Z | ✓ | 1.123 | 0.593 |
| SM_CandelabraFloorA_01 | 0 | 8.5 | 177.0 | 194.0 | 61,62,193 | Z | ✓ | 1.006 | 0.918 |
| SM_LightSmA_Brass | 0 | 10.7 | 40.8 | 62.1 | 20,19,62 | Z | ✓ | 1.001 | 0.656 |
| SM_sf2_pine_06 | 0 | 24.8 | 1596.4 | 1645.9 | 827,843,1705 | Z | (tilted) | 0.965 | 0.936 |
| SM_sf2_pine_07 | 0 | 28.8 | 1979.8 | 2037.4 | 847,889,2158 | Z | ✓ | 0.944 | 0.917 |
| SM_sf2_spruce_02 | 0 | 26.4 | 1377.9 | 1430.7 | 663,755,1483 | Z | ✓ | 0.965 | 0.929 |

**Answer to the mandated question:** yes — for every rotation-0 capsule the authored axis is the
one that ends up on UE **Z**, and where the capsule is the dominant shape the mesh's longest axis
*is* Z (23/25; the exception is a near-spherical bush). The rotated rows confirm the same rule
through the rotator: `roll=90°` puts the long axis on Y, `pitch=90°` on X.

### 4.2 Single-`box` meshes, rotation 0 (30 highest-instance in the load set)

| mesh | inst | authored X,Y,Z (cm) | mesh size x,y,z (cm) | ratio |
|---|---:|---|---|---|
| SM_Urban_Ext_Wall_4x6 | 1125 | 400.1, 30.0, 650.0 | 400.1, 30.0, 650.0 | 1.000,1.000,1.000 |
| SM_FloorConcreteB_4x4 | 758 | 400.0, 400.0, 15.2 | 400.1, 400.0, 15.6 | 1.000,1.000,0.974 |
| SM_CrossBeam_3x3 | 641 | 304.9, 51.6, 308.7 | 304.9, 54.5, 308.2 | 1.000,0.947,1.002 |
| SM_Civic_RailA_1x1 | 581 | 200.0, 33.8, 100.0 | 200.0, 30.2, 100.0 | 1.000,1.120,1.000 |
| SM_Urban_Ext_WindowC_Closed_4x6 | 496 | 400.1, 32.1, 650.0 | 400.8, 57.8, 650.1 | 0.998,0.555,1.000 |
| SM_Prison_WallA_2x6 | 389 | 200.0, 33.4, 600.0 | 201.8, 33.0, 600.4 | 0.991,1.012,0.999 |
| SM_FixtureLightChainMetal25cm | 299 | 27.0, 4.0, 4.0 | 27.8, 6.1, 5.1 | 0.971,0.657,0.785 |
| SM_BodyVent | 282 | 9.3, 8.6, 17.4 | 12.6, 12.6, 17.4 | 0.740,0.681,1.000 |
| SM_Urban_Foundation_Wall_4x6 | 231 | 400.0, 39.5, 650.0 | 400.0, 39.5, 650.0 | 1.000,1.000,1.000 |
| SM_CrossBeam_2x2 | 228 | 203.9, 44.9, 206.9 | 205.6, 53.0, 208.9 | 0.991,0.847,0.991 |
| SM_CrateSetA | 226 | 163.5, 104.7, 95.7 | 167.8, 114.3, 107.2 | 0.975,0.915,0.892 |
| SM_Civic_WallA_Int_4x8 | 210 | 400.0, 24.8, 800.4 | 400.1, 52.2, 800.0 | 1.000,0.475,1.001 |
| SM_FloorPlate | 207 | 200.0, 201.0, 12.9 | 200.0, 201.0, 12.9 | 1.000,1.000,0.997 |
| SM_CablingA | 202 | 11.7, 68.1, 22.0 | 11.7, 68.1, 22.0 | 1.000,1.000,1.000 |
| SM_BaseA | 197 | 178.3, 103.6, 17.8 | 178.3, 103.6, 17.8 | 1.000,1.000,1.000 |
| SM_Civic_WallA_Int_2x8 | 154 | 200.0, 24.8, 800.4 | 200.0, 52.2, 800.0 | 1.000,0.475,1.001 |
| SM_Civic_WallB_Ext_6x8 | 149 | 600.0, 41.7, 850.0 | 600.0, 41.7, 850.0 | 1.000,1.000,1.000 |
| SM_CrossBeam_3x1 | 145 | 303.9, 45.1, 106.9 | 304.3, 52.9, 108.1 | 0.999,0.853,0.989 |
| SM_Chain_2m | 144 | 228.8, 41.5, 20.9 | 228.8, 41.0, 41.0 | 1.000,1.013,0.511 |
| SM_Pipe_Double_Long | 141 | 258.4, 83.5, 40.1 | 258.6, 98.7, 49.5 | 0.999,0.847,0.812 |
| SM_LightBeam_Base | 134 | 23.7, 28.0, 15.9 | 28.0, 28.0, 24.6 | 0.847,1.000,0.644 |
| SM_CrateSetB | 134 | 108.0, 97.1, 87.9 | 110.5, 106.3, 96.9 | 0.978,0.913,0.907 |
| SM_BaseB | 127 | 95.2, 89.1, 17.8 | 95.2, 89.1, 17.8 | 1.000,1.000,1.000 |
| SM_Urban_Ext_Wall_2x6 | 124 | 200.1, 30.0, 650.0 | 200.1, 30.0, 650.0 | 1.000,1.000,1.000 |
| SM_Book02A | 124 | 18.8, 28.3, 10.1 | 18.8, 28.3, 10.1 | 1.000,1.000,1.000 |
| SM_Civic_WallB_Ext_4x8 | 121 | 400.0, 41.7, 850.0 | 400.0, 41.7, 850.0 | 1.000,1.000,1.000 |
| SM_FloorConcreteB_4x2 | 117 | 200.0, 400.0, 13.1 | 200.0, 400.1, 13.0 | 1.000,1.000,1.005 |
| SM_Civic_Rail_Mid_Deco | 117 | 99.5, 80.1, 105.2 | 99.6, 80.1, 105.2 | 0.999,1.000,1.000 |
| SM_Ceiling_Metal_2x2 | 102 | 200.3, 200.5, 47.8 | 200.3, 200.5, 47.8 | 1.000,1.000,1.000 |
| SM_Prison_WallA_6x6 | 102 | 600.0, 32.7, 600.0 | 602.3, 33.6, 600.5 | 0.996,0.973,0.999 |

**Median `X/mesh_size = 0.9999`.** With rotation 0 the authored box *is* the mesh AABB — this is
what decides both the axis order (X→x, Y→y, Z→z in UE, hence `size = (X, Z, Y)` after the swap) and
the full-extent reading (§3.1). 12 of the 30 are 1.000/1.000/1.000 exactly.

---

## 5. Collision enable flags [A]

Representation: there is **no** `NoCollision`/`QueryOnly` boolean. Both are enum *values*:

* `collision_enabled` — from `DefaultInstance.CollisionEnabled` (`parse_collision.py:540-543`,
  emitted mesh-level only when uniform across bodies, `:575-577`).
* `collision_trace_flag` / `complex_as_simple` — from `Properties.CollisionTraceFlag`
  (`:430-434`, mapping `:227-231`), emitted only when present (1,076 bodies, 375 packages).

Whole file (`mesh_collision.json`):

| field | values |
|---|---|
| mesh `collision_enabled` | **absent 1,954** (= default `QueryAndPhysics`), `NoCollision` **31**, `QueryOnly` **7** |
| element `collision_enabled` | `QueryAndPhysics` **8,599**, `PhysicsOnly` **2** (and `None` on 0) |
| mesh `collision_trace_flag` | absent 1,617, `CTF_UseSimpleAsComplex` 359, `CTF_UseComplexAsSimple` **14**, `CTF_UseSimpleAndComplex` 2 |

The 2 `PhysicsOnly` elements are `PHYS_ThiefNisha_Dyn__Body/backpack_capsule` and
`PHYS_Lantern/pivot_capsule` — `PhysicsAsset` (skeletal) bodies, never a static mesh.

Guildhall load set (the set that matters):

| state | paths | instances | notes |
|---|---:|---:|---|
| `NoCollision` | 12 | 337 | `SM_LeavesPileC` 140, `SM_LightBeam` 134, `Cobweb_*` 27, `SM_PosterWanted{A..E}` 40 — all profile `NoCollision` |
| `QueryOnly` | 7 | 158 | `SM_sphere_50segments` 57 (profile `None`, also **`CTF_UseComplexAsSimple`**), `SM_sf2_bush_largeA` 51 / `SM_sf2_bush_03` 22 / `SM_sf2_bush_small01` 15 / `SM_sf2_bush_smallB` 9 (`HidingSpot`), `SM_Basketball` 3 (`Projectile`), `SM_BushB` 1 |
| default `QueryAndPhysics` | 870 | 23,953 | |
| `CTF_UseComplexAsSimple` | 1 | 57 | `SM_sphere_50segments` — authored simple hull is **ignored**; UE uses the render triangles |
| `CTF_UseSimpleAndComplex` | 1 | 2 | `SM_Civic_ColumnE_1x6` (3 elements): query hits simple **and** complex |

UE semantics ↔ Godot:

* `ECollisionEnabled::NoCollision` → **no collision shape at all**. (Faithful; also frees 337
  instances' worth of shapes.)
* `QueryOnly` → the shape exists and answers traces but produces **no physical response**.
  Godot has no per-shape equivalent on a `StaticBody3D`; the faithful encodings are
  (a) a dedicated `collision_layer` bit not present in any mover's `collision_mask`, added to the
  interaction/LOS query masks, or (b) an `Area3D` (only hit by `collide_with_areas` queries).
  Leaving these on layer 1 makes the HidingSpot bushes solid and breaks “hide inside the bush”;
  dropping them loses the query. **[I]** — this needs a decision from the lead, not a silent default.
  Current port state: layer 1 is world, layer 2 player (`thief_character.gd:511-512`,
  `q.collision_mask = 1` at `:2041`), so a new bit + mask updates are required.
* `QueryAndPhysics` → normal `StaticBody3D` on layer 1 (what the loader already does).
* `CTF_UseComplexAsSimple` → ignore `elements`, use the render trimesh (`SM_sphere_50segments`
  is also `QueryOnly`, so it is a query-only trimesh).

---

## 6. The 107 placed paths with no `mesh_collision` record [A]

| class | paths | what the dump says |
|---|---:|---|
| `BodySetup` export exists but has **no `AggGeom` property** | **94** | `Properties` = `{DefaultInstance}` only; `CollisionProfileName = BlockAll`, `CollisionResponses` populated, `NavCollision` present. Producer skips it (`parse_collision.py:645`: `if kind not in BODY_TYPES or "AggGeom" not in props: continue`), which is also why `counts.empty_body_setup = 0`. |
| **no dump file at all** | **13** | `Test/LevelKits/Graybox/GB_Floor_2x2` (2,119 instances), `GB_Floor_6x6`, `GB_Ceiling_2x2`, `GB_Floor_4x4`, `GB_Floor_3x3`, `SM_Ceiling_DrywallBeam`, `Test/Art/Primitives/SM_Shape_*` … `extracted/json/Test/` contains only 2 files. |

UE rule (authoritative): a `UStaticMeshComponent` with `CollisionTraceFlag = CTF_UseDefaultCollision`
and a mesh with **no simple collision** uses the **complex (triangle) collision for both queries and
physics** — that is exactly what `CTF_UseComplexAsSimple` states explicitly, and it is what the
default falls back to. Confirming details in this data: the 94 meshes still declare
`CollisionProfileName = BlockAll` (they are meant to block) and they carry a cooked `NavCollision`,
which UE only produces from collision geometry.

**Verdict:** for the 94, a `ConcavePolygonShape3D` (`Mesh.create_trimesh_shape()`) from the render
mesh **is the authored answer, not a port invention** — and it is also the only faithful option,
because there is no simple geometry to consume. Two caveats:
* 13/107 have no data either way (Graybox `GB_*`). Their role (floors, ceilings) says solid; the
  repo already treats the Guildhall Graybox floors as a deferred content project, so keep whatever
  the loader does and label it a port decision.
* The port's *name* heuristics (`is_nonblocking`, `CLUTTER_TOKENS`, light shafts, moonshapes) and the
  decorative-sublevel rule are **port decisions that override authored blocking** — e.g.
  `SM_LeafB2` (1,304 instances) is `BlockAll` with no simple collision, so UE makes it a solid
  trimesh. Keep these overrides but count them (`facts-a1.md` §2.6 already lists 552 `hidden_in_game`,
  546 CPD, 50 clutter, 172 non-blocking-name).

---

## 7. Multi-body-setup packages — **do not merge** [A]+[M]

* `body_setups[]` is per **package**, and the package key is `BodySetup.Outer.ObjectPath` minus the
  object suffix (`parse_collision.py:647-653`); `_package_json()` concatenates every body's elements
  into one flat array (`:552-557`).
* **All 1,647 `owner_type: "StaticMesh"` packages have exactly one `body_setups[]` entry** (checked:
  `{1: 1647}`) and therefore all carry the `body_setup` field (`:566-567`).
* The **40** multi-body packages are never mesh assets:

| owner types | packages | example (bodies) |
|---|---:|---|
| `PhysicsAsset` | 19 | one `SkeletalBodySetup` per bone |
| `BrushComponent` | 13 | `Building_Guildhall_POI_Audio` (121) — BSP brushes in a map |
| `BrushComponent` + `SplineMeshComponent` | 5 | `OldManor_Geo` (**211**), `Guildhall_PeripheryA` (170), `Building_Guildhall_POI` (59) |
| `SplineMeshComponent` | 3 | |

Those are **level packages** (map collision), not `SM_` assets, and no level `meshes[].mesh` value
resolves to one. `UStaticMesh` itself has a single `BodySetup` (`UStaticMesh::BodySetup`), which is
the `body_setup` field.

**Rule:** join on the mesh key, take the **one** `body_setups[]` entry whose `owner_type` is
`StaticMesh` (equivalently: the entry `body_setup` names). Never union bodies — for a map package
that would attach a whole level's brush collision to a single actor. (All 889 placed Guildhall paths
are `StaticMesh` with exactly 1 body, so this is a non-issue for the load set, and a trap only if
someone later consumes map packages.)

---

## 8. Projected shape cost, 15-file Guildhall load set [M]

Denominator: the 14 base non-decorative sublevels + `Guildhall_Contract_02`
(`mission_controller.gd:986-1021` + `GameData.get_contract_sublevels(2)`), `Guildhall_SkyboxGeo`
excluded (decorative, `collide=false`).

| metric | value |
|---|---:|
| raw mesh records | 30,031 |
| exact-duplicate transforms (loader dedupe key: mesh+pos+basis+scale+overrides+hidden) | 276 |
| deduped instances | 29,755 |
| deduped instances whose path has authored data | **24,254** |
| … of those `NoCollision` (no shape) | 337 |
| **shaped instances** | **23,917** |
| elements on shaped instances | **38,831** (box 22,721 · convex 14,906 · sphyl 826 · sphere 378) |
| distinct placed paths all-primitive (box/sphere/sphyl only) | 539 (15,983 raw instances) |
| distinct placed paths containing convex | 350 (8,465 raw instances) |

| plan | shapes | bodies @384 | vs caps |
|---|---:|---:|---|
| **(a) one shape per element** | **38,831** | 102 | **> `MAX_TOTAL_SHAPES` 32,000 → `run_tests.gd:501` fails** |
| **(b) 1 coalesced shape for all-primitive meshes, 1 per convex element otherwise** | **30,724** (15,818 + 14,906) | 81 | < 32,000 but **> `MAX_BUILDING_SHAPES` 28,000** (`level_loader.gd:191`) |

Budget constants: `MAX_SHAPES_PER_BODY=384`, `MAX_TOTAL_SHAPES=32000`, `MAX_BUILDING_SHAPES=28000`,
`MAX_CURB_SHAPES=4000` (`level_loader.gd:183-197`); the gate fails at `col_shapes >= 32000`
(`run_tests.gd:501`). Current census is `collision_shapes=24466` (`docs/reports/logs/r8/…`,
`build/qa/w9/logs/p1_baseline_run_tests.log:236`). So the authored plan adds **+6.3 k shapes at
(b)** and **+14.4 k at (a)**, and only (b) even fits. **[I]** If further headroom is needed the
levers, in order of fidelity cost, are: skip `NonBlocking`/clutter name matches (already 172 + 50
raw instances), and merge a multi-element primitive mesh into its *smallest* enclosing primitive
subset — never drop a convex hull of a walkable surface.

**Instance-count reconciliation for the lead:** `facts-a1.md` §2.6 reports 124 duplicates /
24,406 covered instances; the dedupe key there evidently omitted `override_materials` /
`hidden_in_game`. With the loader's own key I get **276** duplicates (29,755 / 24,254), which is
exactly the number in the loader's own comment — “424 instances / 276 surplus draws at identical
transforms” (`level_loader.gd:2484-2486`). Plan shape counts against 24,406, not 24,254, if you
prefer the older denominator: (a) 39,077, (b) 30,900 — the fail/pass verdicts do not change.

---

## 9. Traps and open decisions

1. **`half_extent` is a lie by 2×** (§3.1). The producer field name and `NOTES`
   (`parse_collision.py:146-147`) say half-extent; the data, the engine cube, the UE Python doc
   string and CARLA's exporter all say full extent. Consumers: `size = (X, Z, Y) * 0.01`.
2. **`ElemBox` (`aabb_min/max`) is pre-element-transform** (41/41 measured). It is safe as a
   *raw hull* bound only; never as the placed bound and never for a cheap reject when the transform
   is non-identity (37 hulls / 713 Guildhall instances).
3. **`scale3d` must be applied** (19 load-set hulls), in the element's local axes, before the
   quaternion rotation.
4. **Capsules**: use the docs, not the artist's obvious intent. Three pillars have `Length` equal to
   their height (so the authored capsule overshoots into the floor/ceiling by `Radius`), and 17
   capsules are fatter than they are long. Both are legal only under “Length = cylinder segment”.
5. **`QueryOnly` has no Godot equivalent** and needs an explicit layer decision (§5); the HidingSpot
   bushes (152 instances) depend on it.
6. **`CTF_UseComplexAsSimple`** (14 packages, 1 in Guildhall: `SM_sphere_50segments`, 57 instances)
   means the authored simple elements are **not** what UE collides with.
7. **Zero-extent box** `/Engine/BasicShapes/Plane` (6 instances) → clamp before creating the shape.
8. **`rest_offset` is 0.0 on every element** in the load set (2,205/2,205), so it can be ignored —
   and Godot has no per-shape inflation to honour it anyway.
9. **`tapered_capsule`** count is 0 in the shipped data; no consumer path is needed.
10. **Do not re-join `mesh_collision` keys by res path.** `glb_res_to_ue_path()` handles only
    `Content/` and `Raw/TAT/Content/` (not `Raw/Engine`), while the data keys include
    `/Engine/BasicShapes/*`. Use the level JSON `mesh` string verbatim (facts-a1 §1.6).

---

## 10. Provenance of every measurement in this file

| claim | how |
|---|---|
| dump field names / raw values | `python3` reading `extracted/json/Engine/Content/BasicShapes/{Cube,Sphere,Plane}.json`, `.../Basement/Pillars/SM_PillarBasementA_12m.json`, `.../Props/Containers/Cans/SM_CanA.json` |
| GLB AABB (metres) | stdlib parse of the GLB header + JSON chunk, `accessors[POSITION]` across all primitives; root node has no transform |
| GLB axis map | 3 meshes with asymmetric authored `ExtendedBounds` (office floor Y→Z same sign, wall, can) |
| box full-extent ratio | 453 axis-aligned single-box meshes with a GLB (whole file); 30-mesh Guildhall table in §4.2 |
| rotator fit test | 19 rotated single-box meshes, vertex projections onto the authored axes |
| Godot end-to-end box test | 14 unrotated + 14 rotated shapes: corner AABB vs GLB AABB |
| capsule axis/size | 43 single-sphyl meshes with a GLB (30 tabulated), plus rotated cases |
| convex `ElemBox` pre-transform | 41 non-identity hulls, raw-AABB vs transformed-AABB |
| convex hull ↔ mesh match | 493 single-convex meshes with a GLB |
| counts (§5, §7, §8) | `mesh_collision.json` + the 15 `*.tatlevel.json` meshes arrays |
| UE semantics | `dev.epicgames.com` API docs for `FKSphylElem`, `KTaperedCapsuleElem`, `KBoxElem`; CARLA `CarlaExporter.cpp` box conversion; UE `ECollisionTraceFlag` default rule |

Scripts are throwaway (`/tmp/w9a1_common.py`, `/tmp/w9a1_rot.py`); no repo file other than this
report was written and no Godot process was started.
