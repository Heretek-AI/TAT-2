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
    readonly ConcurrentQueue<string> _errors = new();

    public Exporter(DefaultFileProvider p, Opts o) { _p = p; _o = o; }

    IEnumerable<GameFile> Packages(Func<string, bool>? pathPred = null) =>
        _p.Files.Values.Where(f => (f.Extension == "uasset" || f.Extension == "umap")
                                   && f.Path.StartsWith("TAT/", StringComparison.OrdinalIgnoreCase)
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

    void Count(string kind, bool ok, string? err = null)
    {
        (ok ? _ok : _fail).AddOrUpdate(kind, 1, (_, v) => v + 1);
        if (!ok && err != null && _errors.Count < 5000) _errors.Enqueue($"{kind}: {err}");
    }

    void ForEach(IEnumerable<GameFile> files, string kind, Action<GameFile> act)
    {
        var list = files.ToList();
        var sw = Stopwatch.StartNew(); int done = 0;
        Parallel.ForEach(list, new ParallelOptions { MaxDegreeOfParallelism = _o.Threads }, f =>
        {
            try { act(f); }
            catch (Exception e) { Count(kind, false, $"{f.Path}: {e.GetType().Name}: {Trunc(e.Message)}"); }
            var d = Interlocked.Increment(ref done);
            if (d % 500 == 0) Console.Error.WriteLine($"  {kind} {d}/{list.Count} ({sw.Elapsed.TotalSeconds:F0}s)");
        });
        Console.Error.WriteLine($"  {kind} finished {list.Count} in {sw.Elapsed.TotalSeconds:F0}s");
    }

    static string Trunc(string s) => s.Length > 300 ? s[..300] : s;

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
            catch (Exception e) { Console.WriteLine($"{t}: {e.GetType().Name}: {Trunc(e.Message)}"); }
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

    public void Json() => ForEach(Packages(), "json", DumpJson);

    public void Tables()
    {
        var roots = new[] { "TAT/Content/Gameplay/", "TAT/Content/AI/", "TAT/Content/Missions/", "TAT/Content/Character/", "TAT/Content/Core/", "TAT/Content/StringTables/", "TAT/Content/Maps/", "TAT/Content/UI/", "TAT/Content/Audio/" };
        ForEach(Packages(p => p.EndsWith(".uasset") && roots.Any(p.StartsWith)), "tables", DumpJson);
    }

    void DumpJson(GameFile f)
    {
        var dst = OutPath("json", f.Path, ".json");
        if (!_o.Overwrite && File.Exists(dst)) { Count("json", true); return; }
        var pkg = _p.LoadPackage(f);
        var exps = pkg.GetExports().ToList();
        File.WriteAllText(dst, JsonConvert.SerializeObject(exps, Formatting.Indented));
        Count("json", true);
    }

    public void Levels() => ForEach(Packages(p => p.EndsWith(".umap") || Path.GetFileName(p).StartsWith("BPP_") || Path.GetFileName(p).StartsWith("SV_") || Path.GetFileName(p).StartsWith("S_") || Path.GetFileName(p).StartsWith("SS_") || Path.GetFileName(p).StartsWith("QG_")), "levels", DumpJson);

    public void Materials() => ForEach(Packages(p => p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("MI_") || Path.GetFileName(p).StartsWith("M_") || p.Contains("/Developers/") || p.Contains("/MaterialLibrary/"))), "materials", DumpJson);

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
        ForEach(Packages(p => (p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("T_") || p.Contains("/Textures/") || p.Contains("/UI/") || p.Contains("Icon") || p.Contains("WindowPanels_Oldmanor")
                || Path.GetFileName(p).StartsWith("WindowPanel_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("StorefrontWoodTile_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("TrimFabricFancyA_", StringComparison.Ordinal)
                || Path.GetFileName(p).StartsWith("OldBricksB_", StringComparison.Ordinal))) || (p.EndsWith(".umap") && (p.Contains("Landscape") || p.Contains("BeautifulCorner_Startscreen_P")))), "textures", f =>
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
                if (!_o.Overwrite && File.Exists(dst)) { Count("textures", true); continue; }
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
        var session = new ExportSession { MaxDegreeOfParallelism = _o.Threads };
        var files = Packages(p => p.EndsWith(".uasset") && (_o.Filter != null || Path.GetFileName(p).StartsWith("SM_") || Path.GetFileName(p).StartsWith("SK_") || Path.GetFileName(p).StartsWith("SKM_") || Path.GetFileName(p).StartsWith("GB_") || p.Contains("/Meshes/") || p.Contains("/Mesh/") || p.Contains("/Test/LevelKits/") || p.Contains("/GasLamps/") || p.Contains("/Furniture/Tables/") || p.Contains("/Levers/") || p.Contains("/GeneratedMeshes/") || p.Contains("/Developers/"))).ToList();
        Console.Error.WriteLine($"  queuing {files.Count} mesh packages...");
        foreach (var f in files)
        {
            if (!_o.Overwrite && File.Exists(OutPath("assets", f.Path, ".glb"))) { Count("meshes", true); continue; }
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
            catch (Exception e) { Count("meshes", false, $"{f.Path}: {e.GetType().Name}: {Trunc(e.Message)}"); }
        }
        var results = session.RunAsync(outDir, opts).GetAwaiter().GetResult();
        foreach (var r in results)
        {
            FixBackslashPaths(r.DiskFilePaths);
            Count("meshes", r.Success && (r.DiskFilePaths?.Count ?? 0) > 0, r.Error != null ? $"{r.ObjectPath}: {Trunc(r.Error.Message)}" : null);
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
        var opts = AnimOpts();
        var outDir = Path.Combine(_o.Out, "anims", "usd");
        Directory.CreateDirectory(outDir);
        var session = new ExportSession { MaxDegreeOfParallelism = _o.Threads };
        foreach (var f in Packages(p => p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("AN_") || Path.GetFileName(p).StartsWith("A_") || Path.GetFileName(p).StartsWith("AS_") || p.Contains("/Animation/"))))
        {
            try
            {
                var pkg = _p.LoadPackage(f);
                foreach (var e in pkg.GetExports())
                    if (e is UAnimationAsset anim) session.Add(new AnimationExporter(anim));
            }
            catch (Exception e) { Count("anims", false, $"{f.Path}: {e.GetType().Name}: {Trunc(e.Message)}"); }
        }
        var results = session.RunAsync(outDir, opts).GetAwaiter().GetResult();
        foreach (var r in results)
        {
            FixBackslashPaths(r.DiskFilePaths);
            Count("anims", r.Success && (r.DiskFilePaths?.Count ?? 0) > 0, r.Error != null ? $"{r.ObjectPath}: {Trunc(r.Error.Message)}" : null);
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
                if (!e.ExportType.StartsWith("Ak")) continue;
                File.WriteAllText(OutPath("audio-meta", f.Path, ".json"), JsonConvert.SerializeObject(e, Formatting.Indented));
                Count("audio-pkg", true);
            }
        });
    }

    public void Report()
    {
        foreach (var k in _ok.Keys.Union(_fail.Keys).OrderBy(x => x))
            Console.Error.WriteLine($"[{k}] ok={_ok.GetValueOrDefault(k)} fail={_fail.GetValueOrDefault(k)}");
        if (!_errors.IsEmpty)
        {
            Directory.CreateDirectory(_o.Out);
            File.AppendAllLines(Path.Combine(_o.Out, "errors.log"), _errors);
            Console.Error.WriteLine($"errors -> {Path.Combine(_o.Out, "errors.log")}");
        }
    }
}
