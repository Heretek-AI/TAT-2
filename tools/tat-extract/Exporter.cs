using System.Collections.Concurrent;
using System.Diagnostics;
using System.Security.Cryptography;
using CUE4Parse.FileProvider;
using CUE4Parse.FileProvider.Objects;
using CUE4Parse.UE4.Assets;
using CUE4Parse.UE4.Assets.Exports;
using CUE4Parse.UE4.Assets.Exports.Animation;
using CUE4Parse.UE4.Assets.Exports.Engine;
using CUE4Parse.UE4.Assets.Exports.NavigationSystem;
using CUE4Parse.UE4.Assets.Exports.SkeletalMesh;
using CUE4Parse.UE4.Assets.Exports.StaticMesh;
using CUE4Parse.UE4.Assets.Exports.Texture;
using CUE4Parse_Conversion;
using CUE4Parse_Conversion.Exporters;
using CUE4Parse_Conversion.Options;
using CUE4Parse_Conversion.Textures;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace TatExtract;

public sealed class Exporter
{
    readonly DefaultFileProvider _p;
    readonly Opts _o;
    readonly ConcurrentDictionary<string, int> _ok = new();
    readonly ConcurrentDictionary<string, int> _fail = new();
    readonly ConcurrentDictionary<string, int> _skip = new();
    readonly ConcurrentQueue<string> _errors = new();

    public Exporter(DefaultFileProvider p, Opts o) { _p = p; _o = o; }

    IEnumerable<GameFile> Packages(Func<string, bool>? pathPred = null) =>
        _p.Files.Values.Where(f => (f.Extension == "uasset" || f.Extension == "umap")
                                   && (f.Path.StartsWith("TAT/", StringComparison.OrdinalIgnoreCase)
                                       // task-p1 (P1-1 mesh/material repair): Engine primitives AND
                                       // Engine material/mesh carriers live outside TAT/ but are
                                       // referenced by shipped levels (VFX_SkySearchLight_Mesh binds
                                       // /Engine/EngineMaterials/WorldGridMaterial). Anything else
                                       // under Engine/ is still excluded and counted per-command.
                                       || f.Path.StartsWith("Engine/Content/BasicShapes/", StringComparison.OrdinalIgnoreCase)
                                       || f.Path.StartsWith("Engine/Content/EngineMaterials/", StringComparison.OrdinalIgnoreCase)
                                       || f.Path.StartsWith("Engine/Content/EngineMeshes/", StringComparison.OrdinalIgnoreCase)
                                       // Two engine templates are referenced by the shipped developer
                                       // maps that only became visible once every .umap was emitted.
                                       || f.Path.StartsWith("Engine/Content/MapTemplates/", StringComparison.OrdinalIgnoreCase)
                                       || f.Path.StartsWith("Engine/Content/EngineSky/", StringComparison.OrdinalIgnoreCase))
                                   && (_o.Filter == null || _o.Filter.IsMatch(f.Path))
                                   && (pathPred == null || pathPred(f.Path)))
                       .OrderBy(f => f.Path);

    string OutPath(string sub, string gamePath, string ext)
    {
        var rel = gamePath.StartsWith("TAT/Content/") ? gamePath["TAT/Content/".Length..] : gamePath;
        rel = Path.ChangeExtension(rel, ext);
        var full = Path.Combine(_o.Out, sub, rel);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        return full;
    }

    // Real mesh output path: the export session writes under <out>/assets
    // preserving the FULL game path (assets/TAT/Content/<rel>.glb), while
    // OutPath() strips the TAT/Content/ prefix. The old skip check tested the
    // stripped path that is never written, so it never hit: every run
    // re-exported everything and counted it ok.
    string RealMeshPath(GameFile f) => Path.Combine(_o.Out, "assets", Path.ChangeExtension(f.Path, ".glb")!);

    void Count(string kind, bool ok, string? err = null)
    {
        (ok ? _ok : _fail).AddOrUpdate(kind, 1, (_, v) => v + 1);
        if (!ok && err != null) _errors.Enqueue($"{kind}: {err}");
    }

    // Overwrite-skips and allowlist drops are honest non-work: counted here,
    // never in ok/fail, so ok= means "exported now" and fail= means "errored".
    void CountSkip(string kind, int n = 1)
    {
        if (n <= 0) return;
        _skip.AddOrUpdate(kind, n, (_, v) => v + n);
    }

    void ForEach(IEnumerable<GameFile> files, string kind, Action<GameFile> act)
    {
        var list = files.ToList();
        var sw = Stopwatch.StartNew(); int done = 0;
        Parallel.ForEach(list, new ParallelOptions { MaxDegreeOfParallelism = _o.Threads }, f =>
        {
            try { act(f); }
            catch (Exception e) { Count(kind, false, $"{f.Path}: {e.GetType().Name}: {e.Message}"); }
            var d = Interlocked.Increment(ref done);
            if (d % 500 == 0) Console.Error.WriteLine($"  {kind} {d}/{list.Count} ({sw.Elapsed.TotalSeconds:F0}s)");
        });
        Console.Error.WriteLine($"  {kind} finished {list.Count} in {sw.Elapsed.TotalSeconds:F0}s");
    }

    // ------------------------------------------------------------------ commands
    public void Probe()
    {
        foreach (var t in new[] {
            "TAT/Content/Gameplay/Quests/DT_Contracts_1_to_16.uasset",
            "TAT/Content/Gameplay/Tuning/CT_PlayerStats.uasset",
            "TAT/Content/Character/Player/BP_Player_Thief_Spider.uasset",
            "TAT/Content/Maps/OldManor/OldManor_P.umap" })
        {
            try
            {
                var pkg = _p.LoadPackage(t);
                var exps = pkg.GetExports().ToList();
                Console.WriteLine($"{t}: {exps.Count} exports; types: {string.Join(",", exps.Select(e => e.ExportType).Distinct().Take(10))}");
                var js = JsonConvert.SerializeObject(exps.Take(2), Formatting.Indented);
                Console.WriteLine(js.Length > 1500 ? js[..1500] + "..." : js);
            }
            catch (Exception e) { Console.WriteLine($"{t}: {e.GetType().Name}: {e.Message}"); }
        }
    }

    public void List()
    {
        Directory.CreateDirectory(_o.Out);
        File.WriteAllLines(Path.Combine(_o.Out, "filelist.txt"), _p.Files.Values.Select(f => $"{f.Path}\t{f.Size}").OrderBy(x => x));
        Console.Error.WriteLine($"  {_p.Files.Count} entries");
    }

    public void Raw()
    {
        var exts = new HashSet<string> { "locres", "locmeta", "ini", "ufont", "uproject", "bin", "uplugin", "upluginmanifest", "udic", "wem", "bnk", "json", "txt" };
        var files = _p.Files.Values.Where(f => exts.Contains(f.Extension) && f.Path.StartsWith("TAT/") && (_o.Filter == null || _o.Filter.IsMatch(f.Path)));
        ForEach(files, "raw", f =>
        {
            var full = Path.Combine(_o.Out, "raw", f.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllBytes(full, f.Read());
            Count("raw", true);
        });
    }

    public void Json() => ForEach(Packages(), "json", f => DumpJson(f, "json"));

    public void Tables()
    {
        // Deny-list (documented, unchanged): only DataTable/CurveTable/DataAsset
        // roots below are queued; any .uasset outside these 12 roots is dropped
        // before the parsers ever see it and is counted as tables-filtered.
        // P1-2: Art/ThirdParty/Developers added (Art is 10k files; dumping them
        // is slow but silent loss is worse — parsers glob only known tables).
        var roots = new[] { "TAT/Content/Gameplay/", "TAT/Content/AI/", "TAT/Content/Missions/", "TAT/Content/Character/", "TAT/Content/Core/", "TAT/Content/StringTables/", "TAT/Content/Maps/", "TAT/Content/UI/", "TAT/Content/Audio/", "TAT/Content/Art/", "TAT/Content/ThirdParty/", "TAT/Content/Developers/", "TAT/Content/WwiseAudio/", "TAT/Content/MaterialLibrary/" };
        var candidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var queued = candidates.Where(f => roots.Any(f.Path.StartsWith)).ToList();
        CountSkip("tables-filtered", candidates.Count - queued.Count);
        // Sentinel: log the first skipped table candidates so a future table
        // outside the roots is a visible line, not a silent hole.
        foreach (var s in candidates.Where(f => !roots.Any(f.Path.StartsWith)).Take(20))
            Console.Error.WriteLine($"[tables-filtered] skipped outside roots: {s.Path}");
        ForEach(queued, "tables", f => DumpJson(f, "tables"));
    }

    void DumpJson(GameFile f, string kind)
    {
        var dst = OutPath("json", f.Path, ".json");
        if (!_o.Overwrite && File.Exists(dst)) { CountSkip(kind); return; }
        var pkg = _p.LoadPackage(f);
        var exps = pkg.GetExports().ToList();
        File.WriteAllText(dst, JsonConvert.SerializeObject(exps, Formatting.Indented));
        Count(kind, true);
    }

    public void Levels()
    {
        // Two domains, one dump: every .umap (map files) plus BPP_/SV_/S_/
        // SS_/QG_ blueprint dumps (packed-actor templates re-consumed by
        // parse_tables as actor templates, not levels). The S_ prefix also
        // matches unrelated S_* blueprints (sound/state blueprints); they
        // are dumped, never parsed as levels, and counted below so a future
        // genuine sublevel outside both domains shows as levels-filtered.
        var candidates = Packages().ToList();
        var queued = candidates.Where(f => f.Path.EndsWith(".umap") || Path.GetFileName(f.Path).StartsWith("BPP_") || Path.GetFileName(f.Path).StartsWith("SV_") || Path.GetFileName(f.Path).StartsWith("S_") || Path.GetFileName(f.Path).StartsWith("SS_") || Path.GetFileName(f.Path).StartsWith("QG_")).ToList();
        CountSkip("levels-filtered", candidates.Count - queued.Count);
        Console.Error.WriteLine($"  levels domains: {queued.Count(f => f.Path.EndsWith(".umap"))} umap + {queued.Count(f => !f.Path.EndsWith(".umap"))} blueprint");
        ForEach(queued, "levels", f => DumpJson(f, "levels"));
    }

    // Material packages referenced by mesh sidecars (*.materials.json). The
    // name-based filter alone missed authored materials such as CobwebFogy,
    // BaseMaterial, Mi_Blackjack (lowercase i) and T_LightSm_SconceA_Brass
    // (T_ prefix). Sidecars are written by the meshes command, so the Makefile
    // runs meshes before materials; a missing sidecar tree simply yields an
    // empty set and the path/name filters still apply.
    HashSet<string> SidecarMaterialPackages()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var assets = Path.Combine(_o.Out, "assets");
        if (!Directory.Exists(assets)) return set;
        foreach (var mf in Directory.EnumerateFiles(assets, "*.materials.json", SearchOption.AllDirectories))
        {
            try
            {
                var arr = JArray.Parse(File.ReadAllText(mf));
                foreach (var item in arr.OfType<JObject>())
                {
                    var mat = item["material"]?.ToString();
                    if (string.IsNullOrEmpty(mat)) continue;
                    var pkg = mat.Split('.')[0];
                    if (pkg.StartsWith("/Game/", StringComparison.OrdinalIgnoreCase))
                        set.Add("TAT/Content/" + pkg["/Game/".Length..] + ".uasset");
                    else if (pkg.StartsWith("/Engine/", StringComparison.OrdinalIgnoreCase))
                        set.Add("Engine/Content/" + pkg["/Engine/".Length..] + ".uasset");
                }
            }
            catch { /* malformed sidecar: never fail the whole materials pass */ }
        }
        return set;
    }

    static string RelJsonPath(GameFile f)
    {
        var rel = f.Path.StartsWith("TAT/Content/", StringComparison.OrdinalIgnoreCase)
            ? f.Path["TAT/Content/".Length..]
            : f.Path;
        return Path.ChangeExtension(rel, ".json").Replace('\\', '/');
    }

    public void Materials()
    {
        // Queued: MI_/M_ names (case-insensitive, catches Mi_Blackjack),
        // every /Materials/ and /MaterialLibrary/ package (CobwebFogy,
        // BaseMaterial), /Developers/, Engine material carriers, BasicShapes,
        // and every material referenced by a mesh sidecar (T_LightSm_*).
        // Other material assets never reach parse_materials: materials-filtered.
        var refs = SidecarMaterialPackages();
        var candidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var queued = candidates.Where(f =>
        {
            var name = Path.GetFileNameWithoutExtension(f.Path);
            return name.StartsWith("MI_", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("M_", StringComparison.OrdinalIgnoreCase)
                || f.Path.Contains("/Materials/", StringComparison.OrdinalIgnoreCase)
                || f.Path.Contains("/MaterialLibrary/", StringComparison.OrdinalIgnoreCase)
                || f.Path.Contains("/Developers/", StringComparison.OrdinalIgnoreCase)
                || f.Path.StartsWith("Engine/Content/EngineMaterials/", StringComparison.OrdinalIgnoreCase)
                || f.Path.StartsWith("Engine/Content/BasicShapes/", StringComparison.OrdinalIgnoreCase)
                || refs.Contains(f.Path);
        }).ToList();
        CountSkip("materials-filtered", candidates.Count - queued.Count);
        ForEach(queued, "materials", f => DumpJson(f, "materials"));
        // Explicit index so parse_materials never has to guess which JSON files
        // are material dumps (and never parses a huge level/table by mistake).
        var index = queued.Select(RelJsonPath).OrderBy(x => x, StringComparer.Ordinal).ToList();
        File.WriteAllText(Path.Combine(_o.Out, "materials_index.json"), JsonConvert.SerializeObject(index, Formatting.Indented));
        Console.Error.WriteLine($"  materials index: {index.Count} packages");
    }

    ExportOptions DefaultOpts() => new(
        meshFormat: EMeshFormat.Gltf2,
        naniteMeshFormat: ENaniteMeshFormat.NaniteFirst,
        meshQuality: EMeshQuality.Highest,
        texturePlatform: ETexturePlatform.DesktopMobile,
        textureFormat: ETextureFormat.Png,
        textureQuality: 100,
        exportHdrTexturesAsHdr: false,
        exportAllTextureMips: false,
        materialDepth: default,
        exportMaterials: false,
        exportMorphTargets: true,
        socketFormat: ESocketFormat.Bone,
        compressionFormat: CUE4Parse_Conversion.Writers.UEFormat.Enums.EFileCompressionFormat.None
    );

    ExportOptions AnimOpts() => new(
        meshFormat: EMeshFormat.USD,
        naniteMeshFormat: ENaniteMeshFormat.NaniteFirst,
        meshQuality: EMeshQuality.Highest,
        texturePlatform: ETexturePlatform.DesktopMobile,
        textureFormat: ETextureFormat.Png,
        textureQuality: 100,
        exportHdrTexturesAsHdr: false,
        exportAllTextureMips: false,
        materialDepth: default,
        exportMaterials: false,
        exportMorphTargets: true,
        socketFormat: ESocketFormat.Bone,
        compressionFormat: CUE4Parse_Conversion.Writers.UEFormat.Enums.EFileCompressionFormat.None
    );

    // Textures referenced by material dumps that the T_/path filter misses.
    // Example: MI_WoodBoardsOld streams WoodBoardsOld_D/N/ORM, which live under
    // a non-Textures folder and have no T_ prefix. Read the material index and
    // honour both explicit texture parameters and CachedExpressionData refs.
    HashSet<string> ReferencedTexturePackages()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var indexPath = Path.Combine(_o.Out, "materials_index.json");
        if (!File.Exists(indexPath)) return set;
        var byStem = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var ambiguous = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in _p.Files.Values)
        {
            if (!f.Path.EndsWith(".uasset", StringComparison.OrdinalIgnoreCase)) continue;
            var stem = Path.GetFileNameWithoutExtension(f.Path);
            if (byStem.TryGetValue(stem, out var existing) && !string.Equals(existing, f.Path, StringComparison.OrdinalIgnoreCase))
            {
                ambiguous.Add(stem);
                byStem.Remove(stem);
            }
            else if (!ambiguous.Contains(stem))
            {
                byStem[stem] = f.Path;
            }
        }

        void AddObjectPath(string? objPath)
        {
            if (string.IsNullOrEmpty(objPath)) return;
            var pkg = objPath.Split('.')[0];
            if (pkg.StartsWith("/Game/", StringComparison.OrdinalIgnoreCase))
                set.Add("TAT/Content/" + pkg["/Game/".Length..] + ".uasset");
            else if (pkg.StartsWith("/Engine/", StringComparison.OrdinalIgnoreCase))
                set.Add("Engine/Content/" + pkg["/Engine/".Length..] + ".uasset");
        }

        JArray index;
        try { index = JArray.Parse(File.ReadAllText(indexPath)); }
        catch { return set; }
        foreach (var rel in index.OfType<JValue>())
        {
            var jf = Path.Combine(_o.Out, "json", rel.ToString()!);
            if (!File.Exists(jf)) continue;
            JArray exps;
            try { exps = JArray.Parse(File.ReadAllText(jf)); }
            catch { continue; }
            foreach (var exp in exps.OfType<JObject>())
            {
                var props = exp["Properties"] as JObject;
                if (props != null)
                {
                    foreach (var tv in (props["TextureParameterValues"] as JArray)?.OfType<JObject>() ?? Enumerable.Empty<JObject>())
                        AddObjectPath((tv["ParameterValue"] as JObject)?["ObjectPath"]?.ToString());
                    foreach (var tsd in (props["TextureStreamingData"] as JArray)?.OfType<JObject>() ?? Enumerable.Empty<JObject>())
                    {
                        var name = tsd["TextureName"]?.ToString();
                        if (!string.IsNullOrEmpty(name) && byStem.TryGetValue(name, out var pth))
                            set.Add(pth);
                    }
                }
                var cached = exp["CachedExpressionData"] as JObject;
                if (cached != null)
                {
                    foreach (var rt in (cached["ReferencedTextures"] as JArray)?.OfType<JObject>() ?? Enumerable.Empty<JObject>())
                        AddObjectPath(rt["ObjectPath"]?.ToString());
                }
            }
        }
        return set;
    }

    public void Textures()
    {
        var opts = DefaultOpts();
        var refTextures = ReferencedTexturePackages();
        // Deny-list (documented, unchanged): T_ prefix / /Textures/ / /UI/ /
        // Icon / 4 hardcoded stems for .uasset, 3 hardcoded sources for .umap.
        // Anything else never reaches the decoder: textures-filtered.
        bool TextureQueued(string p) => (p.EndsWith(".uasset") && (refTextures.Contains(p) || Path.GetFileName(p).StartsWith("T_") || p.Contains("/Textures/") || p.Contains("/UI/") || p.Contains("Icon") || p.Contains("WindowPanels_Oldmanor")
                || Path.GetFileName(p).StartsWith("WindowPanel_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("StorefrontWoodTile_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("TrimFabricFancyA_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("OldBricksB_", StringComparison.Ordinal))) || (p.EndsWith(".umap") && (p.Contains("Landscape")
                    || p.Contains("BeautifulCorner_Startscreen_P")
                    || Path.GetFileNameWithoutExtension(p).Equals("OldManor_P", StringComparison.OrdinalIgnoreCase)));
        var textureCandidates = Packages().ToList();
        var textureQueued = textureCandidates.Where(f => TextureQueued(f.Path)).ToList();
        CountSkip("textures-filtered", textureCandidates.Count - textureQueued.Count);
        ForEach(textureQueued, "textures", f =>
        {
            var pkg = _p.LoadPackage(f);
            bool isUmap = f.Path.EndsWith(".umap", StringComparison.OrdinalIgnoreCase);
            foreach (var e in pkg.GetExports())
            {
                if (e is not UTexture2D tex) continue;
                var dst = isUmap
                    ? Path.Combine(Path.ChangeExtension(OutPath("assets", f.Path, ".png"), null), e.Name + ".png")
                    : OutPath("assets", f.Path, ".png");
                if (isUmap) Directory.CreateDirectory(Path.GetDirectoryName(dst)!);
                if (!_o.Overwrite && File.Exists(dst)) { CountSkip("textures"); continue; }
                var decoded = TextureDecoder.Decode(tex, opts.TexturePlatform);
                if (decoded == null) { Count("textures", false, f.Path + ": decode null"); continue; }
                var bytes = TextureEncoder.Encode(decoded, opts, out var ext);
                if (bytes == null) { Count("textures", false, f.Path + ": encode null"); continue; }
                File.WriteAllBytes(Path.ChangeExtension(dst, ext), bytes);
                Count("textures", true);
            }
        });
    }

    public void Meshes()
    {
        var opts = DefaultOpts();
        var outDir = Path.Combine(_o.Out, "assets");
        Directory.CreateDirectory(outDir);
        // Godot scans res://assets/ue/Raw/TAT/** and res://assets/ue/Content/** for the
        // same physical TAT tree (Raw -> extracted/assets, Content -> .../TAT/Content),
        // producing a duplicate UID for every mesh. The ignore must live at the
        // physical TAT root (never under Content/, which would hide the whole tree).
        // Writing it here keeps it alive across `make extract` and clean rebuilds.
        Directory.CreateDirectory(Path.Combine(outDir, "TAT"));
        File.WriteAllText(Path.Combine(outDir, "TAT", ".gdignore"), "");
        var session = new ExportSession { MaxDegreeOfParallelism = _o.Threads };
        // task-1 (round-2 mesh repair): also queue VFX_*/Coin_* meshes and Engine
        // BasicShapes primitives dropped by the SM_/SK_/SKM_/GB_ allowlist.
        // P1-1: also queue /_GENERATED/ baked level merges (OldManor gjasp
        // Box_*/Cylinder_*/Combined_* are real mounted .uasset files cited by
        // shipped tatlevels; Box_/Cylinder_ prefixes match nothing else).
        // Allowlist (documented, unchanged): 6 name prefixes + 9 path
        // substrings; --filter bypasses it (everything matching the regex is
        // queued). Anything else never reaches the session: meshes-filtered.
        bool MeshQueued(string p) => _o.Filter != null || Path.GetFileName(p).StartsWith("SM_") || Path.GetFileName(p).StartsWith("SK_") || Path.GetFileName(p).StartsWith("SKM_") || Path.GetFileName(p).StartsWith("GB_") || Path.GetFileName(p).StartsWith("VFX_") || Path.GetFileName(p).StartsWith("Coin_") || p.Contains("/Meshes/") || p.Contains("/Mesh/") || p.Contains("/Test/LevelKits/") || p.Contains("/GasLamps/") || p.Contains("/Furniture/Tables/") || p.Contains("/Levers/") || p.Contains("/GeneratedMeshes/") || p.Contains("/BasicShapes/") || p.Contains("/Developers/") || p.Contains("/_GENERATED/");
        var meshCandidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var files = meshCandidates.Where(f => MeshQueued(f.Path)).ToList();
        CountSkip("meshes-filtered", meshCandidates.Count - files.Count);
        Console.Error.WriteLine($"  queuing {files.Count} mesh packages...");
        foreach (var f in files)
        {
            if (!_o.Overwrite && File.Exists(RealMeshPath(f))) { CountSkip("meshes"); continue; }
            try
            {
                var pkg = _p.LoadPackage(f);
                foreach (var e in pkg.GetExports())
                {
                    if (e is UStaticMesh sm)
                    {
                        session.Add(new StaticMeshExporter(sm));
                        var mats = (sm.StaticMaterials ?? Array.Empty<FStaticMaterial>()).Select(m => new { slot = m.MaterialSlotName.Text, material = m.MaterialInterface?.ResolvedObject?.GetPathName() }).ToList();
                        File.WriteAllText(OutPath("assets", f.Path, ".materials.json"), JsonConvert.SerializeObject(mats, Formatting.Indented));
                    }
                    else if (e is USkeletalMesh sk)
                    {
                        session.Add(new SkinnedAssetExporter(sk));
                        var mats = (sk.SkeletalMaterials ?? Array.Empty<FSkeletalMaterial>()).Select(m => new { slot = m.MaterialSlotName.Text, material = m.MaterialInterface?.ResolvedObject?.GetPathName() }).ToList();
                        File.WriteAllText(OutPath("assets", f.Path, ".materials.json"), JsonConvert.SerializeObject(mats, Formatting.Indented));
                    }
                }
            }
            catch (Exception e) { Count("meshes", false, $"{f.Path}: {e.GetType().Name}: {e.Message}"); }
        }
        var results = session.RunAsync(outDir, opts).GetAwaiter().GetResult();
        foreach (var r in results)
        {
            FixBackslashPaths(r.DiskFilePaths);
            Count("meshes", r.Success && (r.DiskFilePaths?.Count ?? 0) > 0, r.Error != null ? $"{r.ObjectPath}: {r.Error.Message}" : null);
        }
    }

    static void FixBackslashPaths(IReadOnlyList<string>? paths)
    {
        if (paths == null) return;
        foreach (var p in paths)
        {
            if (!p.Contains('\\')) continue;
            var fixedPath = "/" + p.Replace('\\', '/').TrimStart('/');
            if (File.Exists(p))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(fixedPath)!);
                File.Move(p, fixedPath, true);
            }
        }
    }

    public void Anims()
    {
        // Queued: AN_/A_/AS_ name prefixes plus any asset under an
        // /Animation/ path. The bare A_ prefix is over-broad (matches any
        // A_* asset, not just animation) and AN_* misses unprefixed montages
        // outside /Animation/ paths; both directions are documented here and
        // the drop side is counted as anims-filtered so drift is visible.
        // Narrowing A_ is deliberately NOT done: it could silently drop
        // shipped clips (P2-1).
        var opts = AnimOpts();
        var outDir = Path.Combine(_o.Out, "anims", "usd");
        Directory.CreateDirectory(outDir);
        var session = new ExportSession { MaxDegreeOfParallelism = _o.Threads };
        var animCandidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var animQueued = animCandidates.Where(f => Path.GetFileName(f.Path).StartsWith("AN_") || Path.GetFileName(f.Path).StartsWith("A_") || Path.GetFileName(f.Path).StartsWith("AS_") || f.Path.Contains("/Animation/")).ToList();
        CountSkip("anims-filtered", animCandidates.Count - animQueued.Count);
        foreach (var f in animQueued)
        {
            try
            {
                var pkg = _p.LoadPackage(f);
                foreach (var e in pkg.GetExports())
                    if (e is UAnimationAsset anim) session.Add(new AnimationExporter(anim));
            }
            catch (Exception e) { Count("anims", false, $"{f.Path}: {e.GetType().Name}: {e.Message}"); }
        }
        var results = session.RunAsync(outDir, opts).GetAwaiter().GetResult();
        foreach (var r in results)
        {
            FixBackslashPaths(r.DiskFilePaths);
            Count("anims", r.Success && (r.DiskFilePaths?.Count ?? 0) > 0, r.Error != null ? $"{r.ObjectPath}: {r.Error.Message}" : null);
        }
    }

    public void Audio()
    {
        var raw = _p.Files.Values.Where(f => (f.Extension is "wem" or "bnk" or "ubulk") && f.Path.Contains("Wwise", StringComparison.OrdinalIgnoreCase));
        ForEach(raw, "audio-raw", f =>
        {
            var dst = Path.Combine(_o.Out, "audio", f.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(dst)!);
            File.WriteAllBytes(dst, f.Read());
            Count("audio-raw", true);
        });
        ForEach(Packages(p => p.EndsWith(".uasset") && (p.Contains("/WwiseAudio/") || p.Contains("/Audio/"))), "audio-pkg", f =>
        {
            var pkg = _p.LoadPackage(f);
            foreach (var e in pkg.GetExports())
            {
                // Non-Ak exports inside audio packages (helpers, tooltips,
                // editor-only objects) carry no audio and are skipped —
                // counted, never silent (P2-1).
                if (!e.ExportType.StartsWith("Ak")) { CountSkip("audio-pkg-skipped"); continue; }
                File.WriteAllText(OutPath("audio-meta", f.Path, ".json"), JsonConvert.SerializeObject(e, Formatting.Indented));
                Count("audio-pkg", true);
            }
        });
    }

    // ------------------------------------------------------------------- navmesh
    // The JSON dump loses every tile payload twice over: DetourMeshTile.Tile and
    // FCompressedTileCacheData.CompressedData are both [JsonIgnore], so a property
    // dump keeps only SizeInfo + the Recast layer header. This command re-emits
    // what the serializer dropped:
    //   * the decoded Detour tile (vertices / convex polys / off-mesh links), and
    //   * the exact Oodle-compressed Recast layer payload (concatenated to
    //     <map>.cache.bin) plus its decompressed SHA-256.
    // It never re-serialises raw archive bytes: TileDataSize is recorded but the
    // decoded structure is what a Godot NavigationMesh consumer can use.
    public void Nav()
    {
        var files = Packages(p => p.EndsWith(".umap", StringComparison.OrdinalIgnoreCase)).ToList();
        Console.Error.WriteLine($"  nav: {files.Count} map package(s) after filter");
        ForEach(files, "nav", f =>
        {
            var pkg = _p.LoadPackage(f);
            int navMeshes = 0;
            foreach (var e in pkg.GetExports())
            {
                if (e is not ARecastNavMesh nm || nm.RecastNavMeshImpl == null) continue;
                navMeshes++;
                var dst = OutPath("nav", f.Path, ".json");
                if (!_o.Overwrite && File.Exists(dst)) { CountSkip("nav"); continue; }
                var sw = Stopwatch.StartNew();
                // Keep the JSON deterministic: timings go to stderr, never into
                // the data file (the next lane may hash/diff the artifact).
                var doc = NavDoc(f.Path, e.Name, nm, nm.RecastNavMeshImpl, dst);
                File.WriteAllText(dst, JsonConvert.SerializeObject(doc));
                Count("nav", true);
                var impl = nm.RecastNavMeshImpl;
                Console.Error.WriteLine($"  nav {f.Path}:{e.Name} tiles={impl.DetourMeshTiles.Length} polys={doc["poly_count_total"]} verts={doc["vert_count_total"]} offmesh={doc["offmesh_connection_total"]} cache_bytes={doc["cache_compressed_bytes"]} decompress_fail={doc["cache_decompress_fail"]} in {sw.Elapsed.TotalSeconds:F1}s -> {dst}");
            }
            if (navMeshes == 0) CountSkip("nav-nonavmesh");
        });
    }

    static float R2(float v) => MathF.Round(v, 2);

    static float[] Vec3(CUE4Parse.UE4.Objects.Core.Math.FVector v) => new[] { R2(v.X), R2(v.Y), R2(v.Z) };

    Dictionary<string, object?> NavDoc(string mapPath, string exportName, ARecastNavMesh nm, FPImplRecastNavMesh impl, string jsonPath)
    {
        var cachePath = Path.ChangeExtension(jsonPath, null) + ".cache.bin";
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        using var cacheOut = new FileStream(cachePath, FileMode.Create, FileAccess.Write);
        long cachePos = 0;
        int cacheTiles = 0, decompressOk = 0, decompressFail = 0;
        long compressedBytes = 0, uncompressedBytes = 0;
        int polyTotal = 0, vertTotal = 0, offmeshTotal = 0, offmeshSegTotal = 0;
        var tileDocs = new List<Dictionary<string, object?>>(impl.DetourMeshTiles.Length);
        var areaHistogram = new SortedDictionary<int, int>();
        var flagHistogram = new SortedDictionary<int, int>();

        foreach (var t in impl.DetourMeshTiles)
        {
            if (t == null || t.Tile == null || t.SizeInfo == null) continue;
            var tile = t.Tile;
            var size = t.SizeInfo;
            var h = tile.Header;
            polyTotal += size.PolyCount;
            vertTotal += size.VertCount;
            offmeshTotal += size.OffMeshConCount;
            offmeshSegTotal += size.OffMeshSegConCount;

            var verts = new float[tile.Vertices.Length * 3];
            for (int i = 0; i < tile.Vertices.Length; i++)
            {
                verts[i * 3] = R2(tile.Vertices[i].X);
                verts[i * 3 + 1] = R2(tile.Vertices[i].Y);
                verts[i * 3 + 2] = R2(tile.Vertices[i].Z);
            }

            // Off-mesh polys occupy [OffMeshBase, PolyCount) and carry two verts;
            // they are emitted through OffMeshConnections instead.
            int groundPolys = Math.Min(size.OffMeshBase, tile.Polys.Length);
            var polys = new List<int[]>(groundPolys);
            var polyFlags = new List<int>(groundPolys);
            var polyAreas = new List<int>(groundPolys);
            var polyTypes = new List<int>(groundPolys);
            for (int i = 0; i < groundPolys; i++)
            {
                var poly = tile.Polys[i];
                int n = Math.Min((int)poly.VertCount, 6);
                if (n < 3) continue;
                var idx = new int[n];
                for (int k = 0; k < n; k++) idx[k] = poly.Verts[k];
                polys.Add(idx);
                polyFlags.Add(poly.Flags);
                int area = poly.AreaAndType & 0x3f;
                polyAreas.Add(area);
                polyTypes.Add((poly.AreaAndType >> 6) & 0x3);
                areaHistogram[area] = areaHistogram.GetValueOrDefault(area) + 1;
                flagHistogram[poly.Flags] = flagHistogram.GetValueOrDefault(poly.Flags) + 1;
            }

            var offmesh = new List<Dictionary<string, object?>>(tile.OffMeshConnections.Length);
            foreach (var c in tile.OffMeshConnections)
            {
                offmesh.Add(new Dictionary<string, object?>
                {
                    ["a"] = Vec3(c.Positiona),
                    ["b"] = Vec3(c.Positionb),
                    ["radius"] = R2(c.Radius),
                    ["height"] = R2(c.Height),
                    ["poly"] = (int)c.Poly,
                    ["flags"] = (int)c.Flags,
                });
            }
            offmeshSegTotal += tile.OffMeshSegments.Length;

            Dictionary<string, object?>? cache = null;
            var ccd = t.CompressedTileCacheData;
            if (ccd != null && ccd.CompressedData.Length > 0)
            {
                cacheTiles++;
                compressedBytes += ccd.CompressedData.Length;
                uncompressedBytes += ccd.UncompressedSize;
                cacheOut.Write(ccd.CompressedData);
                var compressedSha = Convert.ToHexString(SHA256.HashData(ccd.CompressedData)).ToLowerInvariant();
                string rawSha = "";
                bool ok = false;
                try
                {
                    var raw = ccd.DecompressData();
                    if (raw.Length == ccd.UncompressedSize)
                    {
                        rawSha = Convert.ToHexString(SHA256.HashData(raw)).ToLowerInvariant();
                        ok = true;
                        decompressOk++;
                    }
                    else decompressFail++;
                }
                catch { decompressFail++; }
                cache = new Dictionary<string, object?>
                {
                    ["offset"] = cachePos,
                    ["compressed_size"] = ccd.CompressedData.Length,
                    ["uncompressed_size"] = ccd.UncompressedSize,
                    ["sha256"] = compressedSha,
                    ["raw_sha256"] = rawSha,
                    ["decompress_ok"] = ok,
                    ["header"] = ccd.Header.HasValue ? new Dictionary<string, object?>
                    {
                        ["version"] = ccd.Header.Value.Version,
                        ["tx"] = ccd.Header.Value.Tx,
                        ["ty"] = ccd.Header.Value.Ty,
                        ["tlayer"] = ccd.Header.Value.TLayer,
                        ["bmin"] = Vec3(ccd.Header.Value.BMin),
                        ["bmax"] = Vec3(ccd.Header.Value.BMax),
                        ["width"] = (int)ccd.Header.Value.Width,
                        ["height"] = (int)ccd.Header.Value.Height,
                        ["min_height"] = (int)ccd.Header.Value.MinHeight,
                        ["max_height"] = (int)ccd.Header.Value.MaxHeight,
                    } : null,
                };
                cachePos += ccd.CompressedData.Length;
            }

            tileDocs.Add(new Dictionary<string, object?>
            {
                ["tx"] = h.X,
                ["ty"] = h.Y,
                ["layer"] = h.Layer,
                ["version"] = h.Version,
                ["resolution"] = (int)h.Resolution,
                ["tile_data_size"] = t.TileDataSize,
                ["poly_count"] = size.PolyCount,
                ["vert_count"] = size.VertCount,
                ["max_link_count"] = size.MaxLinkCount,
                ["detail_tri_count"] = size.DetailTriCount,
                ["bv_node_count"] = size.BvNodeCount,
                ["offmesh_base"] = size.OffMeshBase,
                ["offmesh_count"] = size.OffMeshConCount,
                ["offmesh_segment_count"] = size.OffMeshSegConCount,
                ["cluster_count"] = size.ClusterCount,
                ["bmin"] = Vec3(h.BMin),
                ["bmax"] = Vec3(h.BMax),
                ["verts"] = verts,
                ["polys"] = polys.ToArray(),
                ["poly_flags"] = polyFlags.ToArray(),
                ["poly_areas"] = polyAreas.ToArray(),
                ["poly_types"] = polyTypes.ToArray(),
                ["offmesh"] = offmesh.ToArray(),
                ["cache"] = cache,
            });
        }
        cacheOut.Flush();

        var p = impl.DetourNavMeshParams;
        return new Dictionary<string, object?>
        {
            ["schema"] = "tat2.nav_tiles/1",
            ["map"] = mapPath,
            ["export"] = exportName,
            ["nav_mesh_version"] = nm.NavMeshVersion.ToString(),
            ["agent_height_cm"] = R2(nm.AgentHeight),
            ["agent_radius_cm"] = R2(nm.AgentRadius),
            ["nav_mesh_resolution_params"] = nm.NavMeshResolutionParams?.Select(r => new Dictionary<string, object?>
            {
                ["cell_size"] = R2(r.CellSize),
                ["cell_height"] = R2(r.CellHeight),
                ["agent_max_step_height"] = R2(r.AgentMaxStepHeight),
            }).ToArray(),
            ["tile_width_cm"] = R2(p.TileWidth),
            ["tile_height_cm"] = R2(p.TileHeight),
            ["max_tiles"] = p.MaxTiles,
            ["walkable_height_cm"] = R2(p.WalkableHeight),
            ["walkable_radius_cm"] = R2(p.WalkableRadius),
            ["walkable_climb_cm"] = R2(p.WalkableClimb),
            ["bv_quant_factor"] = p.ResolutionParams?.Select(r => (double)r.BvQuantFactor).ToArray(),
            ["tile_count"] = tileDocs.Count,
            ["poly_count_total"] = polyTotal,
            ["vert_count_total"] = vertTotal,
            ["offmesh_connection_total"] = offmeshTotal,
            ["offmesh_segment_total"] = offmeshSegTotal,
            ["poly_area_histogram"] = areaHistogram.ToDictionary(kv => kv.Key.ToString(), kv => kv.Value),
            ["poly_flag_histogram"] = flagHistogram.ToDictionary(kv => kv.Key.ToString(), kv => kv.Value),
            ["cache_tiles"] = cacheTiles,
            ["cache_compressed_bytes"] = compressedBytes,
            ["cache_uncompressed_bytes"] = uncompressedBytes,
            ["cache_decompress_ok"] = decompressOk,
            ["cache_decompress_fail"] = decompressFail,
            ["cache_bin"] = Path.GetFileName(cachePath),
            ["tiles"] = tileDocs.ToArray(),
        };
    }

    public void Report()
    {
        foreach (var k in _ok.Keys.Union(_fail.Keys).Union(_skip.Keys).OrderBy(x => x))
            Console.Error.WriteLine($"[{k}] ok={_ok.GetValueOrDefault(k)} skip={_skip.GetValueOrDefault(k)} fail={_fail.GetValueOrDefault(k)}");
        // Per-run log: always created/truncated (never appended), headed by a
        // marker binding it to this filelist. The audit gate rejects a missing
        // log, a bare zero-byte log, and a marker whose filelist hash differs.
        var log = Path.Combine(_o.Out, "errors.log");
        Directory.CreateDirectory(_o.Out);
        var filelistPath = Path.Combine(_o.Out, "filelist.txt");
        var filelistSha = File.Exists(filelistPath)
            ? Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(filelistPath))).ToLowerInvariant()
            : "none";
        var lines = new List<string>
        {
            $"# run {DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ} filelist {filelistSha} errors {_errors.Count}"
        };
        lines.AddRange(_errors);
        File.WriteAllLines(log, lines);
        Console.Error.WriteLine($"errors -> {log} ({_errors.Count} entries, this run only)");
    }
}
