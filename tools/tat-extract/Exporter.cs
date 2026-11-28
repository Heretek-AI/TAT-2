using System.Collections.Concurrent;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
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
using CUE4Parse.UE4.Assets.Objects;
using CUE4Parse.UE4.Assets.Objects.Properties;
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
        // roots below are queued; any .uasset outside these roots is dropped
        // before the parsers ever see it and is counted as tables-filtered.
        // P1-2: Art/ThirdParty/Developers added (Art is 10k files; dumping them
        // is slow but silent loss is worse — parsers glob only known tables).
        // P3-3B.4: Destructibles added so GC_ChestTrunkALid and the other
        // GeometryCollection packages reach the parsers (previously only the
        // filtered `json` stage could see them).
        var roots = new[] { "TAT/Content/Gameplay/", "TAT/Content/AI/", "TAT/Content/Missions/", "TAT/Content/Character/", "TAT/Content/Core/", "TAT/Content/StringTables/", "TAT/Content/Maps/", "TAT/Content/UI/", "TAT/Content/Audio/", "TAT/Content/Art/", "TAT/Content/ThirdParty/", "TAT/Content/Developers/", "TAT/Content/WwiseAudio/", "TAT/Content/MaterialLibrary/", "TAT/Content/Destructibles/" };
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
        // SS_/QG_/LS_ blueprint dumps (packed-actor templates re-consumed by
        // parse_tables as actor templates, not levels). LS_ is the authored
        // LevelSequence prefix (e.g. LS_Airship_Launch); it was previously only
        // reachable through the tables root's blanket Art/ dump.
        // The S_ prefix also
        // matches unrelated S_* blueprints (sound/state blueprints); they
        // are dumped, never parsed as levels, and counted below so a future
        // genuine sublevel outside both domains shows as levels-filtered.
        var candidates = Packages().ToList();
        var queued = candidates.Where(f => f.Path.EndsWith(".umap") || Path.GetFileName(f.Path).StartsWith("BPP_") || Path.GetFileName(f.Path).StartsWith("SV_") || Path.GetFileName(f.Path).StartsWith("S_") || Path.GetFileName(f.Path).StartsWith("SS_") || Path.GetFileName(f.Path).StartsWith("QG_") || Path.GetFileName(f.Path).StartsWith("LS_")).ToList();
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

    // P3-3A.4: HDR only for the authored sky cubemaps. The 8-bit PNG path
    // clamps a 1e-4..1e-3 HDR sky to 0 or 1/255 (the measured 0.00005 ambient
    // floor), so the six cube faces are written as Radiance .hdr with their
    // linear values intact. Every other texture command keeps DefaultOpts /
    // AnimOpts (exportHdrTexturesAsHdr: false); do not promote this globally.
    ExportOptions CubemapOpts() => new(
        meshFormat: EMeshFormat.Gltf2,
        naniteMeshFormat: ENaniteMeshFormat.NaniteFirst,
        meshQuality: EMeshQuality.Highest,
        texturePlatform: ETexturePlatform.DesktopMobile,
        textureFormat: ETextureFormat.Png,
        textureQuality: 100,
        exportHdrTexturesAsHdr: true,
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
                if (e is UTexture2DArray arr)
                {
                    // U-4: the UI gem array. The UTexture2D loop below skips it
                    // (a Texture2DArray is not a Texture2D), which is why the
                    // 21-slice T_stealthball_Array payload had no PNGs at all.
                    // Only allowlisted arrays are decoded: each one is a set of
                    // full-size slices with no consumer yet, so an unlisted
                    // array is counted, never silently dumped or dropped.
                    if (isUmap) { CountSkip("textures-array-umap"); continue; }
                    if (!ArrayAllowlist.Contains(Path.GetFileNameWithoutExtension(f.Path)))
                    {
                        CountSkip("textures-array-unlisted");
                        continue;
                    }
                    ExportTextureArray(f, arr, opts);
                    continue;
                }
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

    // U-4 scope: only arrays with a runtime consumer are decoded. The gem
    // array is `T_stealthball_Array` (21 x 256x256 PF_DXT5, 1,376,256 bytes of
    // bulk data). Add a stem here only together with its consumer.
    static readonly HashSet<string> ArrayAllowlist = new(StringComparer.Ordinal)
    {
        "T_stealthball_Array",
    };

    /// <summary>
    /// Decode a UTexture2DArray into one PNG per slice plus a manifest that
    /// records the authored shape and a sha256 per written PNG. The runtime
    /// (`game/src/ui/hud.gd`) reads the manifest; `tools/parse_stealthball_array.py`
    /// derives the slice stats from these PNGs. Kept next to the frame art
    /// (`assets/&lt;package&gt;/slice_NN.png`) so one directory holds the array.
    /// </summary>
    void ExportTextureArray(GameFile f, UTexture2DArray arr, ExportOptions opts)
    {
        var rel = f.Path.StartsWith("TAT/Content/") ? f.Path["TAT/Content/".Length..] : f.Path;
        var stem = Path.GetFileNameWithoutExtension(rel);
        var relDir = (Path.GetDirectoryName(rel) ?? "").Replace('\\', '/');
        var outDir = Path.Combine(_o.Out, "assets", Path.GetDirectoryName(rel) ?? "", stem);
        var manifestPath = Path.Combine(outDir, "manifest.json");
        if (!_o.Overwrite && File.Exists(manifestPath)) { CountSkip("textures-array"); return; }
        Directory.CreateDirectory(outDir);

        var pd = arr.PlatformData;
        var expected = pd?.GetNumSlices() ?? 0;
        var files = new List<object>();
        var failures = new List<string>();
        try
        {
            var parts = TextureDecoder.DecodeTextureArray(arr, opts.TexturePlatform);
            if (parts == null || parts.Length == 0)
                throw new Exception("DecodeTextureArray returned no slices");
            for (int i = 0; i < parts.Length; i++)
            {
                var bytes = TextureEncoder.Encode(parts[i], opts, out var ext);
                if (bytes == null) { failures.Add($"slice {i}: encode null"); continue; }
                var name = $"slice_{i:00}{(ext.StartsWith(".") ? ext : "." + ext)}";
                File.WriteAllBytes(Path.Combine(outDir, name), bytes);
                files.Add(new
                {
                    index = i,
                    file = name,
                    width = parts[i].Width,
                    height = parts[i].Height,
                    bytes = bytes.Length,
                    sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
                });
            }
            if (expected > 0 && files.Count != expected)
                failures.Add($"slice count {files.Count} != PlatformData.GetNumSlices() {expected}");
        }
        catch (Exception ex)
        {
            failures.Add($"{ex.GetType().Name}: {ex.Message}");
        }

        var mip = pd?.Mips is { Length: > 0 } mips ? mips[0] : null;
        var manifest = new
        {
            schema = "tat2.texture2darray/1",
            asset = stem,
            source_package = f.Path,
            export_path = string.IsNullOrEmpty(relDir) ? stem : relDir + "/" + stem,
            width = pd?.SizeX ?? 0,
            height = pd?.SizeY ?? 0,
            slices = expected,
            pixel_format = pd?.PixelFormat ?? "",
            packed_data = pd?.PackedData ?? 0,
            first_mip_to_serialize = pd?.FirstMipToSerialize ?? 0,
            source_mip = mip == null ? null : new
            {
                size_x = mip.SizeX,
                size_y = mip.SizeY,
                size_z = mip.SizeZ,
                flags = mip.BulkData?.BulkDataFlags.ToString(),
                bytes = mip.BulkData?.Header.SizeOnDisk,
            },
            decode = new
            {
                slice_files = files.Count,
                failures,
            },
            slice_files = files,
        };
        File.WriteAllText(manifestPath, JsonConvert.SerializeObject(manifest, Formatting.Indented));
        Count("textures-array", failures.Count == 0 && files.Count > 0,
            failures.Count == 0 ? null : $"{f.Path}: {string.Join("; ", failures)}");
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

    // ------------------------------------------------------------------ cubemaps
    // Authored sky TextureCubes referenced by the shipped weather presets:
    //   Gloomy / MidnightClear* -> /Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01
    //   DenseFog_OldManor      -> /Engine/MapTemplates/daylight
    //   Base / Example*        -> /Game/ThirdParty/.../T_FakeSpecular1
    // None of them can reach Textures(): Cubemap_GroundFloor_01 has no T_
    // prefix and is not under /Textures/, T_FakeSpecular1 lives under a
    // ThirdParty use-case folder, and daylight is an Engine template. The
    // allowlist is therefore by exact package, counted as cubemaps-filtered.
    static readonly string[] AuthoredCubePackages =
    {
        "TAT/Content/MaterialLibrary/Utility/Cubemap_GroundFloor_01.uasset",
        "TAT/Content/ThirdParty/FluidNinjaLive/UseCases/007_SmallWater/T_FakeSpecular1.uasset",
        "Engine/Content/MapTemplates/daylight.uasset",
    };

    // UE ECubeFace order in the cooked TextureCube slice data (the six faces
    // are stacked vertically in one decoded image).
    static readonly string[] CubeFaceNames = { "px", "nx", "py", "ny", "pz", "nz" };

    static string CubeId(string name)
    {
        var sb = new StringBuilder(name.Length + 4);
        for (int i = 0; i < name.Length; i++)
        {
            char c = name[i];
            if (char.IsUpper(c) && i > 0 && (char.IsLower(name[i - 1]) || char.IsDigit(name[i - 1])))
                sb.Append('_');
            sb.Append(char.ToLowerInvariant(c));
        }
        return sb.ToString();
    }

    // Cheap orientation gauge for the integrator: an 8-bit face mean over a
    // strided sample. The sky cube's +Y face should read brighter than -Y.
    static double[]? FaceMean(CUE4Parse_Conversion.Textures.CTexture face)
    {
        try
        {
            using var bmp = face.ToSkBitmap();
            int step = Math.Max(1, Math.Max(bmp.Width, bmp.Height) / 32);
            long r = 0, g = 0, b = 0, n = 0;
            for (int y = 0; y < bmp.Height; y += step)
            {
                for (int x = 0; x < bmp.Width; x += step)
                {
                    var px = bmp.GetPixel(x, y);
                    r += px.Red; g += px.Green; b += px.Blue; n++;
                }
            }
            if (n == 0) return null;
            return new[] { Math.Round(r / (double) n / 255.0, 5), Math.Round(g / (double) n / 255.0, 5), Math.Round(b / (double) n / 255.0, 5) };
        }
        catch
        {
            return null; // diagnostics only; never fail the cube export for it
        }
    }

    // Linear face energy for the HDR path: the loader needs the real
    // irradiance scale (the authored sky cube is ~1e-4..1e-3), which the 8-bit
    // FaceMean clamps to zero. Only raw half/float layouts reach here — a
    // format that Decode did not expand to raw is reported as null, never
    // guessed. Returns RGB means without any gamma transform.
    static double[]? FaceMeanLinear(CTexture face)
    {
        if (!PixelFormatUtils.IsHDR(face.PixelFormat)) return null;
        int w = face.Width, h = face.Height;
        if (w <= 0 || h <= 0) return null;
        int step = Math.Max(1, Math.Max(w, h) / 32);
        var data = face.Data;
        int pixelBytes;
        switch (face.PixelFormat)
        {
            case EPixelFormat.PF_FloatRGBA: pixelBytes = 8; break;      // 4 x half
            case EPixelFormat.PF_A32B32G32R32F: pixelBytes = 16; break; // 4 x float
            case EPixelFormat.PF_R32_FLOAT: pixelBytes = 4; break;      // 1 x float
            default: return null;
        }
        if ((long) w * h * pixelBytes > data.LongLength) return null;
        double r = 0, g = 0, b = 0; long n = 0;
        for (int y = 0; y < h; y += step)
        {
            for (int x = 0; x < w; x += step)
            {
                int o = (y * w + x) * pixelBytes;
                float fr, fg, fb;
                if (face.PixelFormat == EPixelFormat.PF_FloatRGBA)
                {
                    fr = (float) BitConverter.UInt16BitsToHalf((ushort) (data[o] | (data[o + 1] << 8)));
                    fg = (float) BitConverter.UInt16BitsToHalf((ushort) (data[o + 2] | (data[o + 3] << 8)));
                    fb = (float) BitConverter.UInt16BitsToHalf((ushort) (data[o + 4] | (data[o + 5] << 8)));
                }
                else if (face.PixelFormat == EPixelFormat.PF_A32B32G32R32F)
                {
                    fr = BitConverter.ToSingle(data, o);
                    fg = BitConverter.ToSingle(data, o + 4);
                    fb = BitConverter.ToSingle(data, o + 8);
                }
                else
                {
                    fr = fg = fb = BitConverter.ToSingle(data, o);
                }
                if (!float.IsFinite(fr) || !float.IsFinite(fg) || !float.IsFinite(fb)) continue;
                r += fr; g += fg; b += fb; n++;
            }
        }
        if (n == 0) return null;
        return new[] { Math.Round(r / n, 6), Math.Round(g / n, 6), Math.Round(b / n, 6) };
    }

    static string UePath(string path)
    {
        var rel = path.Replace('\\', '/');
        if (rel.StartsWith("TAT/Content/", StringComparison.OrdinalIgnoreCase))
            return "/Game/" + Path.ChangeExtension(rel["TAT/Content/".Length..], null);
        if (rel.StartsWith("Engine/Content/", StringComparison.OrdinalIgnoreCase))
            return "/Engine/" + Path.ChangeExtension(rel["Engine/Content/".Length..], null);
        return "/" + Path.ChangeExtension(rel, null);
    }

    // The pinned CUE4Parse-Conversion 1.2.2.202611 decodes a UTextureCube as one
    // tall CTexture (TextureDecoder.Decode stacks GetNumSlices() faces:
    // sizeY *= 6). CTexture has no Crop() in that assembly, so slice the raw
    // decoded bytes by row: every decoded format here is raw (block formats are
    // expanded by DecodeBytes), so face i is the contiguous run
    // [i * faceH * rowBytes, (i+1) * faceH * rowBytes).
    static CTexture SliceCubeFace(CTexture src, int index, int faceHeight)
    {
        if (!PixelFormatUtils.PixelFormats.TryGetValue(src.PixelFormat, out var info) || info.BlockBytes <= 0)
            throw new InvalidOperationException($"cube face slice: unsupported pixel format {src.PixelFormat}");
        int bpp = info.BlockBytes / (info.BlockSizeX * info.BlockSizeY * info.BlockSizeZ);
        if (bpp <= 0)
            throw new InvalidOperationException($"cube face slice: {src.PixelFormat} has no whole bytes per pixel");
        int rowBytes = src.Width * bpp;
        int faceBytes = rowBytes * faceHeight;
        int offset = faceBytes * index;
        if (index < 0 || offset < 0 || faceBytes <= 0 || offset + faceBytes > src.Data.Length)
            throw new InvalidOperationException(
                $"cube face {index} out of range ({src.Width}x{src.Height}, {src.PixelFormat}, bpp={bpp}, data={src.Data.Length})");
        var slice = new byte[faceBytes];
        Buffer.BlockCopy(src.Data, offset, slice, 0, faceBytes);
        return new CTexture(src.Width, faceHeight, src.PixelFormat, slice);
    }

    public void Cubemaps()
    {
        // HDR face export is scoped to this pass only: .hdr for HDR source
        // formats, unchanged PNG for the 8-bit cubes (daylight / fake specular).
        var opts = CubemapOpts();
        var candidates = Packages(p => p.EndsWith(".uasset")).ToList();
        var wanted = candidates.Where(f => AuthoredCubePackages.Contains(f.Path, StringComparer.OrdinalIgnoreCase)).ToList();
        CountSkip("cubemaps-filtered", candidates.Count - wanted.Count);
        foreach (var missing in AuthoredCubePackages.Where(p => !wanted.Any(f => string.Equals(f.Path, p, StringComparison.OrdinalIgnoreCase))))
            Count("cubemaps", false, missing + ": not in the mount");
        foreach (var f in wanted)
        {
            try
            {
                var pkg = _p.LoadPackage(f);
                int cubes = 0;
                foreach (var e in pkg.GetExports())
                {
                    if (e is not UTextureCube cube) continue;
                    cubes++;
                    var id = CubeId(cube.Name);
                    var dir = Path.Combine(_o.Out, "assets", "TAT", "Content", "Cubemaps", id);
                    var manifest = Path.Combine(dir, "cubemap.json");
                    Directory.CreateDirectory(dir);
                    if (!_o.Overwrite && File.Exists(manifest)) { CountSkip("cubemaps"); continue; }
                    var decoded = TextureDecoder.Decode(cube, opts.TexturePlatform);
                    if (decoded == null) { Count("cubemaps", false, f.Path + ": decode null"); continue; }
                    if (decoded.Height % 6 != 0)
                    {
                        Count("cubemaps", false, $"{f.Path}: decoded {decoded.Width}x{decoded.Height} is not six stacked faces");
                        continue;
                    }
                    int faceH = decoded.Height / 6;
                    if (decoded.Width != faceH)
                    {
                        Count("cubemaps", false, $"{f.Path}: decoded {decoded.Width}x{decoded.Height} is not six square {faceH}px faces");
                        continue;
                    }
                    // A re-run must not leave a stale face_*.png beside the new
                    // face_*.hdr (or vice versa): the manifest names the files,
                    // but the directory should not carry both encodings.
                    if (_o.Overwrite)
                        foreach (var stale in Directory.GetFiles(dir, "face_*"))
                            File.Delete(stale);
                    var faces = new Dictionary<string, string>();
                    var means = new Dictionary<string, double[]>();
                    var meansLinear = new Dictionary<string, double[]>();
                    bool hdrEncoded = PixelFormatUtils.IsHDR(decoded.PixelFormat);
                    bool ok = true;
                    for (int i = 0; i < 6; i++)
                    {
                        var face = SliceCubeFace(decoded, i, faceH);
                        var mean = FaceMean(face);
                        if (mean != null) means[CubeFaceNames[i]] = mean;
                        var meanLinear = FaceMeanLinear(face);
                        if (meanLinear != null) meansLinear[CubeFaceNames[i]] = meanLinear;
                        var bytes = face.Encode(opts, out var ext);
                        if (bytes == null) { ok = false; break; }
                        if (ext != "hdr") hdrEncoded = false;
                        var file = $"face_{CubeFaceNames[i]}.{ext}";
                        File.WriteAllBytes(Path.Combine(dir, file), bytes);
                        faces[CubeFaceNames[i]] = file;
                    }
                    if (!ok) { Count("cubemaps", false, f.Path + ": face encode failed"); continue; }
                    var doc = new Dictionary<string, object?>
                    {
                        ["schema"] = "tat2.cubemap/1",
                        ["id"] = id,
                        ["ue_path"] = UePath(f.Path),
                        ["source_package"] = f.Path,
                        ["width"] = decoded.Width,
                        ["height"] = faceH,
                        ["pixel_format"] = cube.Format.ToString(),
                        ["srgb"] = cube.SRGB,
                        // HDR faces are linear by construction; never label
                        // them srgb even if the source flag is set, or the
                        // loader would apply a second gamma transform.
                        ["hdr"] = hdrEncoded,
                        ["encoding"] = hdrEncoded ? "hdr" : "png",
                        ["transfer"] = hdrEncoded ? "linear" : (cube.SRGB ? "srgb" : "linear"),
                        ["slices"] = 6,
                        ["face_order"] = CubeFaceNames,
                        ["ue_face_order"] = new[] { "PosX", "NegX", "PosY", "NegY", "PosZ", "NegZ" },
                        ["faces"] = faces,
                        ["face_mean_8bit"] = means,
                    };
                    // Real (unclamped) linear face energy for the loader.
                    if (meansLinear.Count > 0) doc["face_mean_linear"] = meansLinear;
                    File.WriteAllText(manifest, JsonConvert.SerializeObject(doc, Formatting.Indented));
                    Count("cubemaps", true);
                    Console.Error.WriteLine($"  cubemap {cube.Name}: {decoded.Width}x{faceH} {decoded.PixelFormat} srgb={cube.SRGB} hdr={hdrEncoded} -> {dir}");
                }
                if (cubes == 0) Count("cubemaps", false, f.Path + ": no UTextureCube export");
            }
            catch (Exception e) { Count("cubemaps", false, $"{f.Path}: {e.GetType().Name}: {e.Message}"); }
        }
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
                // Fail closed on a re-run too: delete the previous JSON before
                // decoding so a 7+ vertex refusal cannot leave stale tiles for
                // parse_nav to consume.
                if (File.Exists(dst)) File.Delete(dst);
                // Keep the JSON deterministic: timings go to stderr, never into
                // the data file (the next lane may hash/diff the artifact).
                var doc = NavDoc(f.Path, e.Name, nm, nm.RecastNavMeshImpl, dst);
                File.WriteAllText(dst, JsonConvert.SerializeObject(doc));
                Count("nav", true);
                var impl = nm.RecastNavMeshImpl;
                Console.Error.WriteLine($"  nav {f.Path}:{e.Name} tiles={impl.DetourMeshTiles.Length} polys={doc["poly_count_total"]} verts={doc["vert_count_total"]} offmesh={doc["offmesh_connection_total"]} max_poly_verts={doc["max_poly_verts"]} cache_bytes={doc["cache_compressed_bytes"]} decompress_fail={doc["cache_decompress_fail"]} in {sw.Elapsed.TotalSeconds:F1}s -> {dst}");
            }
            if (navMeshes == 0) CountSkip("nav-nonavmesh");
        });
    }

    static float R2(float v) => MathF.Round(v, 2);

    static float[] Vec3(CUE4Parse.UE4.Objects.Core.Math.FVector v) => new[] { R2(v.X), R2(v.Y), R2(v.Z) };

    // ------------------------------------------------------- property helpers
    // ARecastNavMesh exposes no typed SupportedAreas/NavDataConfig members in
    // CUE4Parse 1.2.2 (reflection shows only the base UObject properties), so
    // the authored area table and agent config are read from the generic
    // property tags. A missing tag is emitted as an empty value, never guessed.
    static FPropertyTag? FindProp(UObject o, string name) =>
        o.Properties?.FirstOrDefault(p => p.Name.Text == name);

    static IEnumerable<FPropertyTag> StructProps(StructProperty? st)
    {
        if (st?.Value == null) return Enumerable.Empty<FPropertyTag>();
        return st.Value.StructType is FStructFallback fb ? fb.Properties : Enumerable.Empty<FPropertyTag>();
    }

    static IEnumerable<FPropertyTag> StructProps(FPropertyTag? tag) =>
        tag?.Tag is StructProperty st ? StructProps(st) : Enumerable.Empty<FPropertyTag>();

    static double? NumOf(FPropertyTag? tag) => tag?.Tag switch
    {
        Int8Property p => p.Value,
        Int16Property p => p.Value,
        IntProperty p => p.Value,
        Int64Property p => p.Value,
        UInt16Property p => p.Value,
        UInt32Property p => p.Value,
        UInt64Property p => p.Value,
        FloatProperty p => p.Value,
        _ => null,
    };

    Dictionary<string, object?> NavDoc(string mapPath, string exportName, ARecastNavMesh nm, FPImplRecastNavMesh impl, string jsonPath)
    {
        var cachePath = Path.ChangeExtension(jsonPath, null) + ".cache.bin";
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        using var cacheOut = new FileStream(cachePath, FileMode.Create, FileAccess.Write);
        long cachePos = 0;
        int cacheTiles = 0, decompressOk = 0, decompressFail = 0;
        long compressedBytes = 0, uncompressedBytes = 0;
        int polyTotal = 0, vertTotal = 0, offmeshTotal = 0, offmeshSegTotal = 0;
        int maxPolyVerts = 0;
        var tileDocs = new List<Dictionary<string, object?>>(impl.DetourMeshTiles.Length);
        var areaHistogram = new SortedDictionary<int, int>();
        var flagHistogram = new SortedDictionary<int, int>();
        var supportedAreas = new List<Dictionary<string, object?>>();
        var areaTag = FindProp(nm, "SupportedAreas");
        if (areaTag?.Tag is ArrayProperty areaArray && areaArray.Value != null)
        {
            foreach (var item in areaArray.Value.Properties)
            {
                if (item is not StructProperty st) continue;
                var fields = new Dictionary<string, FPropertyTag>();
                foreach (var f in StructProps(st)) fields[f.Name.Text] = f;
                string className = "";
                if (fields.TryGetValue("AreaClassName", out var cn))
                {
                    // The typed FNavAgentSelectorSupportedAreas serializer emits
                    // the class name as FString (StrProperty), not FName.
                    className = cn.Tag switch
                    {
                        StrProperty sp => sp.Value,
                        NameProperty np => np.Value.Text,
                        _ => "",
                    };
                }
                double? areaId = fields.TryGetValue("AreaID", out var aid) ? NumOf(aid) : null;
                if (className == "" || areaId == null) continue;
                supportedAreas.Add(new Dictionary<string, object?>
                {
                    ["id"] = (int)areaId.Value,
                    ["class"] = className,
                });
            }
        }
        var navDataConfig = new Dictionary<string, object?>();
        foreach (var f in StructProps(FindProp(nm, "NavDataConfig")))
        {
            double? value = NumOf(f);
            if (value == null) continue;
            switch (f.Name.Text)
            {
                case "AgentRadius": navDataConfig["agent_radius_cm"] = R2((float)value.Value); break;
                case "AgentHeight": navDataConfig["agent_height_cm"] = R2((float)value.Value); break;
                case "AgentStepHeight": navDataConfig["agent_step_height_cm"] = R2((float)value.Value); break;
            }
        }

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
                // Detour stores at most 6 verts per convex poly (RC_MESH_NULL_IDX
                // beyond VertCount). The old Math.Min(…, 6) silently truncated a
                // malformed authored poly; fail closed instead so a 7+ vert poly
                // can never produce a plausible-looking navmesh.
                int n = (int)poly.VertCount;
                if (n > 6)
                    throw new InvalidDataException(
                        $"tile {h.X},{h.Y} layer {h.Layer} poly {i} has {n} verts; Detour max is 6 (refusing to clamp)");
                if (n < 3) continue;
                maxPolyVerts = Math.Max(maxPolyVerts, n);
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
        double? cfgRadius = navDataConfig.TryGetValue("agent_radius_cm", out var cr) ? Convert.ToDouble(cr) : null;
        double? cfgHeight = navDataConfig.TryGetValue("agent_height_cm", out var ch) ? Convert.ToDouble(ch) : null;
        return new Dictionary<string, object?>
        {
            ["schema"] = "tat2.nav_tiles/1",
            ["map"] = mapPath,
            ["export"] = exportName,
            ["nav_mesh_version"] = nm.NavMeshVersion.ToString(),
            // The typed AgentHeight/AgentRadius read as 0 in CUE4Parse 1.2.2;
            // prefer the authored NavDataConfig, then the Detour params.
            ["agent_height_cm"] = R2((float)(cfgHeight ?? p.WalkableHeight)),
            ["agent_radius_cm"] = R2((float)(cfgRadius ?? p.WalkableRadius)),
            ["nav_data_config"] = navDataConfig,
            ["supported_areas"] = supportedAreas,
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
            ["max_poly_verts"] = maxPolyVerts,
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
