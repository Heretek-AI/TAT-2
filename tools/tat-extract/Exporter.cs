using System.Collections.Concurrent;
using System.Diagnostics;
using CUE4Parse.FileProvider;
using CUE4Parse.FileProvider.Objects;
using CUE4Parse.UE4.Assets;
using CUE4Parse.UE4.Assets.Exports;
using CUE4Parse.UE4.Assets.Exports.Animation;
using CUE4Parse.UE4.Assets.Exports.Engine;
using CUE4Parse.UE4.Assets.Exports.SkeletalMesh;
using CUE4Parse.UE4.Assets.Exports.StaticMesh;
using CUE4Parse.UE4.Assets.Exports.Texture;
using CUE4Parse_Conversion;
using CUE4Parse_Conversion.Exporters;
using CUE4Parse_Conversion.Options;
using CUE4Parse_Conversion.Textures;
using Newtonsoft.Json;

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

    public void Materials()
    {
        // Queued: MI_/M_ names + /Developers/ + /MaterialLibrary/ paths.
        // Other material assets never reach parse_materials: materials-filtered.
        // P1-1: Engine material carriers (WorldGridMaterial, bound by the
        // repaired VFX mesh) are queued explicitly — the MI_/M_ prefixes
        // never match Engine names, so the Packages() widening alone would
        // still drop them here.
        var candidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var queued = candidates.Where(f => Path.GetFileName(f.Path).StartsWith("MI_") || Path.GetFileName(f.Path).StartsWith("M_") || f.Path.Contains("/Developers/") || f.Path.Contains("/MaterialLibrary/") || f.Path.StartsWith("Engine/Content/EngineMaterials/")).ToList();
        CountSkip("materials-filtered", candidates.Count - queued.Count);
        ForEach(queued, "materials", f => DumpJson(f, "materials"));
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

    public void Textures()
    {
        var opts = DefaultOpts();
        // Deny-list (documented, unchanged): T_ prefix / /Textures/ / /UI/ /
        // Icon / 4 hardcoded stems for .uasset, 3 hardcoded sources for .umap.
        // Anything else never reaches the decoder: textures-filtered.
        bool TextureQueued(string p) => (p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("T_") || p.Contains("/Textures/") || p.Contains("/UI/") || p.Contains("Icon") || p.Contains("WindowPanels_Oldmanor")
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

    public void Report()
    {
        foreach (var k in _ok.Keys.Union(_fail.Keys).Union(_skip.Keys).OrderBy(x => x))
            Console.Error.WriteLine($"[{k}] ok={_ok.GetValueOrDefault(k)} skip={_skip.GetValueOrDefault(k)} fail={_fail.GetValueOrDefault(k)}");
        // Per-run log: truncated on open (never appended), so stale errors
        // from prior runs cannot pass as current-run signal. Deleted when the
        // run is clean so an old errors.log never lingers.
        var log = Path.Combine(_o.Out, "errors.log");
        if (!_errors.IsEmpty)
        {
            Directory.CreateDirectory(_o.Out);
            File.WriteAllLines(log, _errors);
            Console.Error.WriteLine($"errors -> {log} ({_errors.Count} entries, this run only)");
        }
        else if (File.Exists(log)) File.Delete(log);
    }
}
