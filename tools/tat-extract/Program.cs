// tat-extract: dumps Thick As Thieves content from the user's own Steam install.
// Usage: tat-extract <command> [--game DIR] [--out DIR] [--usmap FILE] [--filter REGEX]
//   probe                 mount + parse a few known assets
//   list                  write file list to OUT/filelist.txt
//   json                  every package matching filter -> OUT/json/<path>.json (property dump)
//   tables                DataTables/CurveTables/DataAssets under Gameplay|AI|Missions|Maps -> json
//   textures              Texture2D -> OUT/assets/<path>.png
//   meshes                StaticMesh/SkeletalMesh (+ materials) -> OUT/assets/<path>.gltf
//   anims                 AnimSequence -> gltf
//   levels                .umap -> OUT/levels/<path>.json (actors + transforms)
//   audio                 WwiseAudio media (.wem) and raw sound -> OUT/audio
//   raw                   non-uasset files (locres, ini, ufont, uproject, AssetRegistry) -> OUT/raw
using System.Text.RegularExpressions;
using CUE4Parse.Compression;
using CUE4Parse.FileProvider;
using CUE4Parse.MappingsProvider.Usmap;
using CUE4Parse.UE4.Versions;

namespace TatExtract;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length == 0) { Console.WriteLine("usage: tat-extract <probe|list|json|tables|textures|meshes|anims|levels|audio|raw|all> [opts]"); return 1; }
        var opt = Opts.Parse(args.Skip(1).ToArray());
        OodleHelper.Initialize(EnsureOodle());
        var provider = new DefaultFileProvider(Path.Combine(opt.Game, "TAT/Content/Paks"), SearchOption.TopDirectoryOnly,
            new VersionContainer(EGame.GAME_UE5_5));
        if (opt.Usmap != null && File.Exists(opt.Usmap)) provider.MappingsContainer = new FileUsmapTypeMappingsProvider(opt.Usmap);
        else Console.Error.WriteLine("WARNING: no usmap; unversioned packages will fail");
        provider.Initialize();
        provider.Mount();
        Console.Error.WriteLine($"mounted {provider.Files.Count} files");
        // P1-1 sentinel: the mount is a single hard-coded pak dir, so any
        // sibling pak chunk / patch dir / DLC dir placed beside it is
        // invisible to every command. Never silently continue: name each one.
        try
        {
            var pakDir = Path.Combine(opt.Game, "TAT/Content/Paks");
            var parent = Directory.GetParent(pakDir.TrimEnd(Path.DirectorySeparatorChar));
            if (parent != null && Directory.Exists(parent.FullName))
            {
                foreach (var sib in Directory.GetFileSystemEntries(parent.FullName).OrderBy(x => x))
                {
                    var name = Path.GetFileName(sib);
                    if (name.Equals("Paks", StringComparison.OrdinalIgnoreCase)) continue;
                    bool looksPak = name.EndsWith(".pak", StringComparison.OrdinalIgnoreCase)
                        || name.EndsWith(".utoc", StringComparison.OrdinalIgnoreCase)
                        || name.EndsWith(".ucas", StringComparison.OrdinalIgnoreCase)
                        || (Directory.Exists(sib) && Directory.GetFiles(sib, "*.pak").Length > 0);
                    if (looksPak)
                        Console.Error.WriteLine($"WARNING: sibling pak entry NOT mounted (single-pak mount): {sib}");
                }
            }
        }
        catch (Exception e) { Console.Error.WriteLine($"WARNING: sibling-pak scan failed: {e.Message}"); }
        var ex = new Exporter(provider, opt);
        var cmds = args[0] == "all" ? new[] { "list", "raw", "tables", "levels", "textures", "meshes", "audio" } : new[] { args[0] };
        foreach (var c in cmds)
        {
            Console.Error.WriteLine($"== {c}");
            switch (c)
            {
                case "probe": ex.Probe(); break;
                case "list": ex.List(); break;
                case "json": ex.Json(); break;
                case "tables": ex.Tables(); break;
                case "textures": ex.Textures(); break;
                case "meshes": ex.Meshes(); break;
                case "anims": ex.Anims(); break;
                case "levels": ex.Levels(); break;
                case "materials": ex.Materials(); break;
                case "audio": ex.Audio(); break;
                case "raw": ex.Raw(); break;
                default: Console.Error.WriteLine("unknown " + c); return 1;
            }
        }
        ex.Report();
        return 0;
    }

    static string EnsureOodle()
    {
        var path = Path.Combine(AppContext.BaseDirectory, OodleHelper.OodleFileName);
        if (!File.Exists(path) && !OodleHelper.DownloadOodleDll(ref path)) throw new Exception("could not fetch oodle");
        return path;
    }
}

public sealed class Opts
{
    public string Game = Environment.GetEnvironmentVariable("TAT_GAME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local/share/Steam/steamapps/common/Thick As Thieves");
    public string Out = "extracted";
    public string? Usmap;
    public Regex? Filter;
    public int Threads = Environment.ProcessorCount;
    public bool Overwrite;

    public static Opts Parse(string[] a)
    {
        var o = new Opts();
        for (int i = 0; i < a.Length; i++)
        {
            switch (a[i])
            {
                case "--game": o.Game = a[++i]; break;
                case "--out": o.Out = a[++i]; break;
                case "--usmap": o.Usmap = a[++i]; break;
                case "--filter": o.Filter = new Regex(a[++i], RegexOptions.IgnoreCase | RegexOptions.Compiled, TimeSpan.FromSeconds(2)); break;
                case "--threads": o.Threads = int.Parse(a[++i]); break;
                case "--overwrite": o.Overwrite = true; break;
            }
        }
        o.Usmap ??= FindUsmap();
        return o;
    }

    static string? FindUsmap()
    {
        foreach (var d in new[] { "tools/ue4ss/output", "../ue4ss/output", "../../tools/ue4ss/output" })
            if (Directory.Exists(d)) { var f = Directory.GetFiles(d, "*.usmap").FirstOrDefault(); if (f != null) return f; }
        return null;
    }
}
