// utf8-mirror.exe — clangd が読めない文字コード（CP932・UTF-16）のソースを、UTF-8 に直した写しに
// して、元のパスのまま clangd に見せる（clang の VFS overlay＝-vfsoverlay）。ソースは変えない。
//
// 何のためにあるか: clangd はソースを UTF-8 として読む。CP932 のヘッダでは、行末が「表」「能」など
// 2 バイト目が 0x5C（\）の文字のコメントが行継続になり、次の行（宣言・メンバ・#endif）が clangd から
// 消える。日本語より後ろの列もずれる。MSVC は CP932 として読むのでビルドは通る＝ソースは CP932 の
// まま置きたい（2026-11-04 に clangd 23.1 で実測。nvim/lua/config/utf8_mirror.lua が呼ぶ）。
//
// 置き場（リポには何も書かない）:
//   %LOCALAPPDATA%\utf8-mirror\<フォルダ名>-<ハッシュ>\files\…     写し（リポからの相対パス。フォルダ名は 200 文字まで）
//                                                   \overlay.json  clang の VFS overlay
//                                                   \index.tsv     前回の判定（更新日時と大きさが同じファイルは読まない）
//   %LOCALAPPDATA%\clangd\config.yaml の「# >>> utf8-mirror <root>」の節
//     そのリポの C/C++ に -vfsoverlay を足す（If: PathMatch）。MSVC の /source-charset と
//     /execution-charset は外す（clang は UTF-8 しか受け付けず、全ファイルの 1 行目がエラーになる）。
//
// overlay の書き方（実測で決めた）:
//   ファイルごとの項目にする。directory-remap は clangd が飛び先に写しのパスを返す（写しを編集してしまう）
//   写しを書いてから overlay を替え、写しを消すのは overlay を替えた後（載っている写しが欠けると、
//   そのヘッダが「見つからない」になる）
//
// 限界: clangd の裏のインデックスは、.cpp 本体を overlay を通さずにディスクから読む（overlay が効くのは
//   #include されるファイルだけ）。開いているファイルはエディタが UTF-8 で渡すので問題ない。
//
// 長いパス（260 文字以上）: ファイルに触る所はすべて \\?\ を付けて呼ぶ（Long）。写しのパスは
//   %LOCALAPPDATA%\utf8-mirror\…\files\ の分だけ元より長くなるので、元が 260 文字に収まっていても越える。
//   OS の LongPathsEnabled には頼らない（csc の exe は longPathAware を宣言しないので、どのみち効かない）。
//   .NET Framework が \\?\ を受け付けるのは 4.6.2 以降の扱い＝下の TargetFramework（無いと 4.0 の扱いになり、
//   \\?\ を付けても PathTooLongException。2026-11-05 に実測）。clangd（LLVM）は長いパスを自分で扱える。
//   名前 1 つは \\?\ でも 255 文字まで（NTFS）なので、こちらで作る名前（一時ファイル・置き場・排他の名前）は
//   元の名前より長くしない
//
// 使い方:
//   utf8-mirror enable <root>              写しを作り、clangd の設定に節を足す
//   utf8-mirror sync <root> [--file F]...  写しを今のソースに合わせる（--file があれば F だけ見る）
//   utf8-mirror disable <root>             節を外し、写しを消す
//   utf8-mirror status [<root>]            有効なリポ
//   共通: --json（機械向け）・--clangd-config <path>・--state <dir>（試験用に置き場を変える）
//
// ビルドは install.ps1 がやる（Windows 同梱の csc.exe）:
//   csc /optimize /out:tools\bin\utf8-mirror.exe tools\cp932\Utf8Mirror.cs

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.6.2")]

internal static class Utf8Mirror
{
    private static readonly HashSet<string> Extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".h", ".hh", ".hpp", ".hxx", ".h++", ".inl", ".ipp", ".tcc", ".tlh", ".tli",
        ".c", ".cc", ".cpp", ".cxx", ".c++",
    };

    private const string Begin = "# >>> utf8-mirror ";
    private const string End = "# <<< utf8-mirror ";

    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    private static readonly Encoding Cp932 =
        Encoding.GetEncoding(932, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback);

    // index.tsv の 1 行。Kind: 'u' = UTF-8（ASCII・BOM 付きを含む）・'s' = CP932・'w' = UTF-16（BOM 付き）・
    // 'x' = どれでもない（写さない）
    private sealed class Entry
    {
        public char Kind;
        public long Ticks;
        public long Size;
    }

    private sealed class Options
    {
        public string Command;
        public string Root;
        public readonly List<string> Files = new List<string>();
        public bool Json;
        public string ClangdConfig;
        public string State;
    }

    private sealed class Result
    {
        public int Mirrored;
        public int Added;
        public int Updated;
        public int Removed;
        public readonly List<string> Errors = new List<string>();
    }

    private sealed class Node
    {
        public readonly SortedDictionary<string, Node> Dirs = new SortedDictionary<string, Node>(StringComparer.OrdinalIgnoreCase);
        public readonly SortedDictionary<string, string> Files = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    // ---------------------------------------------------------------- 判定

    // 厳密な UTF-8（冗長な表現とサロゲートは不可）
    private static bool IsUtf8(byte[] b)
    {
        int i = 0;
        while (i < b.Length)
        {
            byte c = b[i];
            if (c < 0x80) { i++; continue; }
            int len;
            byte lo = 0x80, hi = 0xBF;
            if (c >= 0xC2 && c <= 0xDF) len = 2;
            else if (c == 0xE0) { len = 3; lo = 0xA0; }
            else if (c == 0xED) { len = 3; hi = 0x9F; }
            else if (c >= 0xE1 && c <= 0xEF) len = 3;
            else if (c == 0xF0) { len = 4; lo = 0x90; }
            else if (c == 0xF4) { len = 4; hi = 0x8F; }
            else if (c >= 0xF1 && c <= 0xF3) len = 4;
            else return false;
            if (i + len > b.Length) return false;
            if (b[i + 1] < lo || b[i + 1] > hi) return false;
            for (int j = i + 2; j < i + len; j++)
            {
                if (b[j] < 0x80 || b[j] > 0xBF) return false;
            }
            i += len;
        }
        return true;
    }

    private static char Classify(byte[] b, out string text)
    {
        text = null;
        if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) return 'u';
        if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE)
        {
            text = Encoding.Unicode.GetString(b, 2, b.Length - 2);
            return 'w';
        }
        if (b.Length >= 2 && b[0] == 0xFE && b[1] == 0xFF)
        {
            text = Encoding.BigEndianUnicode.GetString(b, 2, b.Length - 2);
            return 'w';
        }
        if (IsUtf8(b)) return 'u';
        try
        {
            text = Cp932.GetString(b);
            return 's';
        }
        catch (DecoderFallbackException)
        {
            return 'x';
        }
    }

    // ---------------------------------------------------------------- パス

    private static string Normalize(string path)
    {
        string full = Path.GetFullPath(path).TrimEnd('\\', '/');
        if (full.Length <= 2) throw new ArgumentException("root must not be a drive: " + path);
        return full;
    }

    private static string Slash(string path)
    {
        return path.Replace('\\', '/');
    }

    // ファイルに触る時のパス（\\?\ 付き。冒頭の「長いパス」）。\\?\ は正規化されないので先に絶対パスにする
    private static string Long(string path)
    {
        if (path.StartsWith(@"\\?\")) return path;
        string full = Path.GetFullPath(path);
        return full.StartsWith(@"\\") ? @"\\?\UNC\" + full.Substring(2) : @"\\?\" + full;
    }

    // Long の逆（一覧で返ってきたパスを、元のパスの形に戻す）
    private static string Short(string path)
    {
        if (path.StartsWith(@"\\?\UNC\")) return @"\\" + path.Substring(8);
        return path.StartsWith(@"\\?\") ? path.Substring(4) : path;
    }

    private static string Hash8(string s)
    {
        using (var sha = SHA1.Create())
        {
            byte[] hash = sha.ComputeHash(Utf8.GetBytes(s));
            return BitConverter.ToString(hash, 0, 4).Replace("-", "").ToLowerInvariant();
        }
    }

    // リポの印（置き場の名前と排他の名前に使う）
    private static string RootHash(string root)
    {
        return Hash8(Slash(root).ToLowerInvariant());
    }

    private static string StateDir(string state, string root)
    {
        var name = new StringBuilder();
        foreach (char c in Path.GetFileName(root))
        {
            name.Append(c < 0x80 && (char.IsLetterOrDigit(c) || c == '-' || c == '_' || c == '.') ? c : '_');
        }
        // 名前 1 つは 255 文字まで。フォルダ名が長いリポは頭の 200 文字だけ使う（区別はハッシュでつく）
        if (name.Length > 200) name.Length = 200;
        return Path.Combine(state, name + "-" + RootHash(root));
    }

    // 一覧を取れなかったフォルダは errors に足す（黙って飛ばすと、その下のヘッダが写されないまま気づけない）。
    // 権限の無いフォルダだけは今までどおり黙って飛ばす
    private static IEnumerable<string> Walk(string root, List<string> errors)
    {
        var stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            string dir = stack.Pop();
            string[] subdirs, files;
            try
            {
                subdirs = Directory.GetDirectories(Long(dir)).Select(Short).ToArray();
                files = Directory.GetFiles(Long(dir)).Select(Short).ToArray();
            }
            catch (UnauthorizedAccessException) { continue; }
            catch (IOException e)
            {
                errors.Add((dir.Length > root.Length ? Slash(dir.Substring(root.Length + 1)) : ".") + "/: " + e.Message);
                continue;
            }
            foreach (string f in files)
            {
                if (Extensions.Contains(Path.GetExtension(f))) yield return f;
            }
            foreach (string d in subdirs)
            {
                string name = Path.GetFileName(d);
                // .git・.vs・.cache（clangd のインデックス）・.svn と、junction（ループを避ける）は見ない
                if (name.StartsWith(".") || name.Equals("node_modules", StringComparison.OrdinalIgnoreCase)) continue;
                try
                {
                    if ((File.GetAttributes(Long(d)) & FileAttributes.ReparsePoint) != 0) continue;
                }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }
                stack.Push(d);
            }
        }
    }

    // ---------------------------------------------------------------- 書き込み

    // tmp を dest に差し替える（clangd が読んでいる途中でも、古いか新しいかのどちらかが見える）
    private static void Replace(string tmp, string dest)
    {
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                if (File.Exists(Long(dest))) File.Replace(Long(tmp), Long(dest), null);
                else File.Move(Long(tmp), Long(dest));
                return;
            }
            catch (IOException)
            {
                if (attempt >= 4) throw;
            }
            catch (UnauthorizedAccessException)
            {
                if (attempt >= 4) throw;
            }
            Thread.Sleep(50);
        }
    }

    // 中身が同じなら書かない（更新日時が変わると clangd が読み直す）。書いたら true
    private static bool WriteIfChanged(string path, byte[] data)
    {
        if (File.Exists(Long(path)))
        {
            byte[] old = File.ReadAllBytes(Long(path));
            if (old.Length == data.Length && old.SequenceEqual(data)) return false;
        }
        Directory.CreateDirectory(Long(Path.GetDirectoryName(path)));
        // <名前>.tmp にしない（255 文字の名前だと上限を越える）
        string tmp = Path.Combine(Path.GetDirectoryName(path), "~" + Hash8(Path.GetFileName(path).ToLowerInvariant()) + ".tmp");
        File.WriteAllBytes(Long(tmp), data);
        Replace(tmp, path);
        return true;
    }

    private static Dictionary<string, Entry> LoadIndex(string path)
    {
        var index = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(Long(path))) return index;
        foreach (string line in File.ReadAllLines(Long(path), Utf8))
        {
            string[] f = line.Split('\t');
            long ticks, size;
            if (f.Length != 4 || f[0].Length != 1 || !long.TryParse(f[1], out ticks) || !long.TryParse(f[2], out size)) continue;
            index[f[3]] = new Entry { Kind = f[0][0], Ticks = ticks, Size = size };
        }
        return index;
    }

    private static void SaveIndex(string path, Dictionary<string, Entry> index)
    {
        var sb = new StringBuilder();
        foreach (var kv in index.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase))
        {
            sb.Append(kv.Value.Kind).Append('\t').Append(kv.Value.Ticks).Append('\t').Append(kv.Value.Size).Append('\t').Append(kv.Key).Append('\n');
        }
        WriteIfChanged(path, Utf8.GetBytes(sb.ToString()));
    }

    private static string JsonString(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (char c in s)
        {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
            else sb.Append(c);
        }
        return sb.Append('"').ToString();
    }

    private static void EmitDir(StringBuilder sb, string name, Node node, string indent)
    {
        sb.Append(indent).Append("{ \"type\": \"directory\", \"name\": ").Append(JsonString(name)).Append(", \"contents\": [\n");
        var items = new List<string>();
        foreach (var kv in node.Dirs)
        {
            var child = new StringBuilder();
            EmitDir(child, kv.Key, kv.Value, indent + "  ");
            items.Add(child.ToString());
        }
        foreach (var kv in node.Files)
        {
            items.Add(indent + "  { \"type\": \"file\", \"name\": " + JsonString(kv.Key) + ", \"external-contents\": " + JsonString(kv.Value) + " }");
        }
        sb.Append(string.Join(",\n", items)).Append('\n').Append(indent).Append("] }");
    }

    // 写しの相対パス（files/ から）を、元のパスで見える overlay にする。external-contents は
    // overlay.json からの相対（overlay-relative）。名前の大文字小文字は区別しない（Windows）
    private static string BuildOverlay(string root, IEnumerable<string> rels)
    {
        var tree = new Node();
        bool any = false;
        foreach (string rel in rels)
        {
            any = true;
            string[] parts = rel.Split('/');
            Node node = tree;
            for (int i = 0; i < parts.Length - 1; i++)
            {
                Node child;
                if (!node.Dirs.TryGetValue(parts[i], out child))
                {
                    child = new Node();
                    node.Dirs[parts[i]] = child;
                }
                node = child;
            }
            node.Files[parts[parts.Length - 1]] = "files/" + rel;
        }
        var sb = new StringBuilder();
        sb.Append("{\n  \"version\": 0,\n  \"case-sensitive\": \"false\",\n  \"use-external-names\": false,\n");
        sb.Append("  \"overlay-relative\": true,\n  \"roots\": [\n");
        if (any)
        {
            EmitDir(sb, Slash(root), tree, "    ");
            sb.Append('\n');
        }
        sb.Append("  ]\n}\n");
        return sb.ToString();
    }

    // ---------------------------------------------------------------- sync

    private static Result Sync(string root, string dir, List<string> only)
    {
        var result = new Result();
        string indexPath = Path.Combine(dir, "index.tsv");
        string filesDir = Path.Combine(dir, "files");
        Dictionary<string, Entry> index = LoadIndex(indexPath);
        var before = new HashSet<string>(index.Where(kv => kv.Value.Kind == 's' || kv.Value.Kind == 'w').Select(kv => kv.Key), StringComparer.OrdinalIgnoreCase);

        IEnumerable<string> targets;
        if (only.Count > 0)
        {
            targets = only.Select(f => Path.GetFullPath(f));
        }
        else
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var all = Walk(root, result.Errors).ToList();
            foreach (string f in all) seen.Add(Slash(f.Substring(root.Length + 1)));
            foreach (string gone in index.Keys.Where(k => !seen.Contains(k)).ToList()) index.Remove(gone);
            targets = all;
        }

        foreach (string file in targets)
        {
            if (!file.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase)) continue;
            string rel = Slash(file.Substring(root.Length + 1));
            string mirror = Path.Combine(filesDir, rel.Replace('/', '\\'));
            try
            {
                var info = new FileInfo(Long(file));
                if (!info.Exists)
                {
                    index.Remove(rel);
                    continue;
                }
                Entry entry;
                bool known = index.TryGetValue(rel, out entry) && entry.Ticks == info.LastWriteTimeUtc.Ticks && entry.Size == info.Length;
                if (known && (entry.Kind == 'u' || entry.Kind == 'x' || File.Exists(Long(mirror)))) continue;
                string text;
                char kind = Classify(File.ReadAllBytes(Long(file)), out text);
                if (text != null && WriteIfChanged(mirror, Utf8.GetBytes(text)))
                {
                    if (before.Contains(rel)) result.Updated++;
                    else result.Added++;
                }
                index[rel] = new Entry { Kind = kind, Ticks = info.LastWriteTimeUtc.Ticks, Size = info.Length };
            }
            catch (IOException e)
            {
                result.Errors.Add(rel + ": " + e.Message);
            }
            catch (UnauthorizedAccessException e)
            {
                result.Errors.Add(rel + ": " + e.Message);
            }
        }

        var after = index.Where(kv => kv.Value.Kind == 's' || kv.Value.Kind == 'w').Select(kv => kv.Key).ToList();
        result.Mirrored = after.Count;
        Directory.CreateDirectory(Long(dir));
        WriteIfChanged(Path.Combine(dir, "overlay.json"), Utf8.GetBytes(BuildOverlay(root, after)));

        // overlay から外した後に写しを消す
        var keep = new HashSet<string>(after, StringComparer.OrdinalIgnoreCase);
        foreach (string rel in before.Where(r => !keep.Contains(r)))
        {
            string mirror = Path.Combine(filesDir, rel.Replace('/', '\\'));
            try
            {
                if (File.Exists(Long(mirror))) File.Delete(Long(mirror));
                result.Removed++;
            }
            catch (IOException e)
            {
                result.Errors.Add(rel + ": " + e.Message);
            }
            catch (UnauthorizedAccessException e)
            {
                result.Errors.Add(rel + ": " + e.Message);
            }
        }
        SaveIndex(indexPath, index);
        return result;
    }

    // ---------------------------------------------------------------- clangd の設定

    private static string RegexEscape(string s)
    {
        var sb = new StringBuilder();
        foreach (char c in s)
        {
            if (".^$|()[]{}*+?\\".IndexOf(c) >= 0) sb.Append('\\');
            sb.Append(c);
        }
        return sb.ToString();
    }

    private static string YamlQuote(string s)
    {
        return "'" + s.Replace("'", "''") + "'";
    }

    private static string Block(string root, string overlay, string nl)
    {
        string r = Slash(root);
        return string.Join(nl, new[]
        {
            "---",
            Begin + r,
            "# dotfiles の tools/bin/utf8-mirror.exe が書いた節（手で書き換えない。外す＝utf8-mirror disable <root>）。",
            "# CP932 のソースを UTF-8 に直した写しを clangd に見せる（仕組みは tools/cp932/Utf8Mirror.cs の冒頭）。",
            "If:",
            // PathMatch は / 区切りの絶対パスに当たり、大文字小文字は区別しない（2026-11-04 実測）
            "  PathMatch: " + YamlQuote(RegexEscape(r) + "/.*"),
            "CompileFlags:",
            "  Add: [-vfsoverlay, " + YamlQuote(Slash(overlay)) + "]",
            "  Remove: [/source-charset:*, /execution-charset:*]",
            End + r,
        }) + nl;
    }

    // root の節を差し替える（block が null なら外す）。他の内容は触らない
    private static void SetBlock(string config, string root, string overlay)
    {
        string text = File.Exists(Long(config)) ? File.ReadAllText(Long(config), Utf8) : "";
        string nl = text.Contains("\r\n") ? "\r\n" : "\n";
        var lines = text.Replace("\r\n", "\n").Split('\n').ToList();
        string begin = Begin + Slash(root), end = End + Slash(root);
        int from = lines.FindIndex(l => l.Trim().Equals(begin, StringComparison.OrdinalIgnoreCase));
        if (from >= 0)
        {
            int to = lines.FindIndex(from, l => l.Trim().Equals(end, StringComparison.OrdinalIgnoreCase));
            if (to < 0) throw new InvalidDataException("no end marker for " + begin + " in " + config);
            if (from > 0 && lines[from - 1].Trim() == "---") from--;
            lines.RemoveRange(from, to - from + 1);
        }
        string rest = string.Join(nl, lines).TrimEnd('\r', '\n');
        if (overlay == null)
        {
            if (rest.Trim().Length == 0)
            {
                if (File.Exists(Long(config))) File.Delete(Long(config));
                return;
            }
            rest += nl;
        }
        else
        {
            rest = (rest.Length > 0 ? rest + nl : "") + Block(root, overlay, nl);
        }
        Directory.CreateDirectory(Long(Path.GetDirectoryName(config)));
        WriteIfChanged(config, Utf8.GetBytes(rest));
    }

    private static List<string> EnabledRoots(string config)
    {
        var roots = new List<string>();
        if (!File.Exists(Long(config))) return roots;
        foreach (string line in File.ReadAllLines(Long(config), Utf8))
        {
            if (line.StartsWith(Begin)) roots.Add(line.Substring(Begin.Length).Trim());
        }
        return roots;
    }

    // ---------------------------------------------------------------- main

    private static void Print(string s)
    {
        byte[] b = Utf8.GetBytes(s + "\n");
        using (Stream o = Console.OpenStandardOutput()) o.Write(b, 0, b.Length);
    }

    private static string SyncJson(string root, string overlay, Result r)
    {
        return "{\"root\": " + JsonString(Slash(root)) + ", \"overlay\": " + JsonString(Slash(overlay)) +
            ", \"mirrored\": " + r.Mirrored + ", \"added\": " + r.Added + ", \"updated\": " + r.Updated +
            ", \"removed\": " + r.Removed + ", \"errors\": [" + string.Join(", ", r.Errors.Select(e => JsonString(e))) + "]}";
    }

    private static Options Parse(string[] args)
    {
        var o = new Options();
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "--json") o.Json = true;
            else if (a == "--file" && i + 1 < args.Length) o.Files.Add(args[++i]);
            else if (a == "--clangd-config" && i + 1 < args.Length) o.ClangdConfig = args[++i];
            else if (a == "--state" && i + 1 < args.Length) o.State = args[++i];
            else if (a.StartsWith("--")) throw new ArgumentException("unknown option: " + a);
            else if (o.Command == null) o.Command = a;
            else if (o.Root == null) o.Root = a;
            else throw new ArgumentException("unexpected argument: " + a);
        }
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (o.ClangdConfig == null) o.ClangdConfig = Path.Combine(local, "clangd", "config.yaml");
        if (o.State == null) o.State = Path.Combine(local, "utf8-mirror");
        return o;
    }

    private static int Main(string[] args)
    {
        Options o;
        try
        {
            o = Parse(args);
            if (o.Command == null || (o.Command != "status" && o.Root == null)) throw new ArgumentException("usage");
        }
        catch (ArgumentException e)
        {
            Console.Error.WriteLine("utf8-mirror: " + e.Message);
            Console.Error.WriteLine("usage: utf8-mirror enable|sync|disable <root> [--file F]... [--json]  /  utf8-mirror status [<root>] [--json]");
            return 2;
        }
        try
        {
            if (o.Command == "status")
            {
                var items = new List<string>();
                foreach (string r in EnabledRoots(o.ClangdConfig))
                {
                    if (o.Root != null && !Slash(Normalize(o.Root)).Equals(r, StringComparison.OrdinalIgnoreCase)) continue;
                    string dir = StateDir(o.State, Normalize(r));
                    int n = LoadIndex(Path.Combine(dir, "index.tsv")).Count(kv => kv.Value.Kind == 's' || kv.Value.Kind == 'w');
                    items.Add(o.Json
                        ? "{\"root\": " + JsonString(r) + ", \"mirrored\": " + n + ", \"state\": " + JsonString(Slash(dir)) + "}"
                        : r + "  (" + n + " files, " + dir + ")");
                }
                Print(o.Json ? "[" + string.Join(", ", items) + "]" : string.Join("\n", items));
                return 0;
            }

            string root = Normalize(o.Root);
            if (!Directory.Exists(Long(root))) throw new DirectoryNotFoundException(root);
            string stateDir = StateDir(o.State, root);
            string overlay = Path.Combine(stateDir, "overlay.json");
            // 同じリポを 2 つが同時に触らない（保存とフォーカスの復帰が重なる時）
            // 名前は 260 文字まで（置き場の名前だと長いフォルダ名で越える）
            using (var mutex = new Mutex(false, "Local\\utf8-mirror-" + RootHash(root)))
            {
                bool owned = false;
                try
                {
                    try
                    {
                        owned = mutex.WaitOne(60000);
                    }
                    catch (AbandonedMutexException)
                    {
                        owned = true;
                    }
                    if (!owned) throw new TimeoutException("another utf8-mirror is running for " + root);

                    if (o.Command == "disable")
                    {
                        SetBlock(o.ClangdConfig, root, null);
                        if (Directory.Exists(Long(stateDir))) Directory.Delete(Long(stateDir), true);
                        Print(o.Json ? "{\"root\": " + JsonString(Slash(root)) + "}" : "disabled " + Slash(root));
                        return 0;
                    }
                    if (o.Command != "sync" && o.Command != "enable") throw new ArgumentException("unknown command: " + o.Command);
                    Result r = Sync(root, stateDir, o.Files);
                    if (o.Command == "enable") SetBlock(o.ClangdConfig, root, overlay);
                    Print(o.Json ? SyncJson(root, overlay, r)
                        : string.Format("{0}: {1} files mirrored (+{2} ~{3} -{4}){5}", Slash(root), r.Mirrored, r.Added, r.Updated, r.Removed,
                            r.Errors.Count > 0 ? "\n" + string.Join("\n", r.Errors) : ""));
                    return r.Errors.Count > 0 ? 1 : 0;
                }
                finally
                {
                    if (owned) mutex.ReleaseMutex();
                }
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("utf8-mirror: " + e.Message);
            return 1;
        }
    }
}
