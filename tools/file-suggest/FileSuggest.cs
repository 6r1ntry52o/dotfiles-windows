// file-suggest.exe — Claude Code の @ の候補（設定 fileSuggestion）。どこで起動しても、
// プロジェクトのファイルに加えて vault の note/ のノートを出す。
//
//   入力  標準入力に JSON {"query": "<@ の後ろに打った文字>"}。環境変数 CLAUDE_PROJECT_DIR
//   出力  候補のパスを 1 行に 1 つ、良い順に 15 個まで（UTF-8）
//
// なぜ要るか: Claude Code の組み込みの候補は起動した場所の中しか出さない。
// permissions.additionalDirectories や --add-dir で vault を足しても @ には出ない（2026-11-03 実測）。
// fileSuggestion は組み込みの候補を丸ごと置き換えるので、プロジェクトのファイルもここで出す。
//
//   プロジェクト  rg --files（.gitignore で外すものは出さない＝組み込みと同じ）→ 無ければ
//                 git ls-files → どちらも無ければ素で辿る。フォルダも出す（末尾が /）
//   ノート        <vault>/note/**/*.md を絶対パスで（どのリポから選んでも同じノートが添付される）。
//                 vault は ~/.dotfiles.json の vault。プロジェクトが vault 自身なら足さない（重複）
//
// 並び: 名前が query で始まる → 名前に含む → パスに含む → パスに query の字が順に現れる。
// 同じ段ではプロジェクトが先、短いパスが先。大文字小文字は区別しない。
// query が note/ かノートの置き場の絶対パス（~/… も）で始まる時はノートだけを探す
// （vault の外のプロジェクトの時）。
//
// 打つたびに呼ばれるので、PowerShell（起動に 0.25 秒）ではなく exe にした。
// ビルドは tools/Install-AiAgents.ps1 がやる（Windows 同梱の csc.exe。C# 5 まで）:
//   csc /optimize /out:tools\bin\file-suggest.exe tools\file-suggest\FileSuggest.cs

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

internal static class FileSuggest
{
    private const int MaxShown = 15;
    // Claude Code は 5 秒で待つのをやめる。ホームのような巨大なフォルダで起動しても間に合うよう、
    // 一覧はここで打ち切る（2026-11-03: ホームで 3 秒・20 万件の時は全体で 4.2 秒かかった）
    private const int MaxProjectFiles = 100000;
    private const int ListTimeoutMs = 1500;

    private sealed class Candidate
    {
        public string Path;  // 出す文字列
        public string Key;   // 照らし合わせる文字列（小文字・/ 区切り）
        public int Kind;     // 0=プロジェクト 1=ノート
        public int Score;
    }

    private static int Main()
    {
        try
        {
            var utf8 = new UTF8Encoding(false);
            string input = new StreamReader(Console.OpenStandardInput(), utf8).ReadToEnd();
            string query = JsonString(input, "query") ?? "";
            string q = query.Replace('\\', '/').ToLowerInvariant();

            string project = Environment.GetEnvironmentVariable("CLAUDE_PROJECT_DIR");
            if (string.IsNullOrEmpty(project) || !Directory.Exists(project)) project = null;
            string noteDir = NoteDir();
            if (noteDir != null && project != null && IsUnder(noteDir, project)) noteDir = null;

            // note/… か、ノートの置き場の絶対パス（~/… も）で打ち始めたら、ノートだけを探す
            bool notesOnly = false;
            string match = q;
            if (noteDir != null)
            {
                string noteRoot = noteDir.Replace('\\', '/').TrimEnd('/').ToLowerInvariant() + "/";
                string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).Replace('\\', '/').TrimEnd('/').ToLowerInvariant();
                string qAbs = q.StartsWith("~/") ? home + q.Substring(1) : q;
                if (q.StartsWith("note/")) { notesOnly = true; match = q.Substring(5); }
                else if (qAbs.StartsWith(noteRoot)) { notesOnly = true; match = qAbs.Substring(noteRoot.Length); }
            }

            var candidates = new List<Candidate>();
            if (project != null && !notesOnly) AddProject(candidates, project);
            if (noteDir != null) AddNotes(candidates, noteDir);

            var hits = new List<Candidate>();
            foreach (var c in candidates)
            {
                c.Score = Score(c.Key, match);
                if (c.Score >= 0) hits.Add(c);
            }
            hits.Sort(delegate (Candidate a, Candidate b)
            {
                int d = a.Score.CompareTo(b.Score);
                if (d == 0) d = a.Kind.CompareTo(b.Kind);
                if (d == 0) d = a.Key.Length.CompareTo(b.Key.Length);
                if (d == 0) d = string.CompareOrdinal(a.Path, b.Path);
                return d;
            });

            var output = new StreamWriter(Console.OpenStandardOutput(), utf8);
            output.NewLine = "\n";
            for (int i = 0; i < hits.Count && i < MaxShown; i++) output.WriteLine(hits[i].Path);
            output.Flush();
            return 0;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("file-suggest: " + e.Message);
            return 1;
        }
    }

    // 0=名前が q で始まる 1=名前に含む 2=パスに含む 3=字が順に現れる -1=当たらない
    private static int Score(string key, string q)
    {
        if (q.Length == 0) return 2;
        string trimmed = key.TrimEnd('/');
        string name = trimmed.Substring(trimmed.LastIndexOf('/') + 1);
        if (name.StartsWith(q, StringComparison.Ordinal)) return 0;
        if (name.IndexOf(q, StringComparison.Ordinal) >= 0) return 1;
        if (key.IndexOf(q, StringComparison.Ordinal) >= 0) return 2;
        int i = 0;
        foreach (char ch in key)
        {
            if (i < q.Length && ch == q[i]) i++;
        }
        return i == q.Length ? 3 : -1;
    }

    private static void AddProject(List<Candidate> list, string project)
    {
        List<string> files = Run("rg", "--files --hidden --glob \"!.git/\"", project);
        if (files == null) files = Run("git", "-c core.quotepath=off ls-files", project);
        if (files == null) files = Walk(project);
        var dirs = new HashSet<string>();
        foreach (string f in files)
        {
            string rel = f.Replace('\\', '/');
            if (rel.StartsWith("./")) rel = rel.Substring(2);
            if (rel.Length == 0) continue;
            list.Add(new Candidate { Path = rel, Key = rel.ToLowerInvariant(), Kind = 0 });
            int k = rel.LastIndexOf('/');
            while (k > 0)
            {
                string d = rel.Substring(0, k + 1);
                if (!dirs.Add(d)) break;
                list.Add(new Candidate { Path = d, Key = d.ToLowerInvariant(), Kind = 0 });
                k = rel.LastIndexOf('/', k - 1);
            }
        }
    }

    private static void AddNotes(List<Candidate> list, string noteDir)
    {
        string root = noteDir.Replace('\\', '/').TrimEnd('/') + "/";
        foreach (string f in Directory.EnumerateFiles(noteDir, "*.md", SearchOption.AllDirectories))
        {
            string abs = f.Replace('\\', '/');
            // ノートは note/ の中のパスで照らす（vault より上のフォルダ名には当てない）
            list.Add(new Candidate { Path = abs, Key = abs.Substring(root.Length).ToLowerInvariant(), Kind = 1 });
        }
    }

    // コマンドの出力（相対パス）。コマンドが無い・失敗した時は null
    private static List<string> Run(string exe, string args, string dir)
    {
        try
        {
            var psi = new ProcessStartInfo(exe, args);
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false);
            var lines = new List<string>();
            using (var p = new Process())
            {
                p.StartInfo = psi;
                p.OutputDataReceived += delegate (object s, DataReceivedEventArgs e)
                {
                    if (e.Data != null && lines.Count < MaxProjectFiles) lines.Add(e.Data);
                };
                p.ErrorDataReceived += delegate (object s, DataReceivedEventArgs e) { };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                if (!p.WaitForExit(ListTimeoutMs))
                {
                    try { p.Kill(); } catch { }
                    return lines; // 大きすぎるフォルダ（ホームなど）では、そこまでで出す
                }
                p.WaitForExit();
                // rg は「ファイルが 1 つも無い」でも 1 を返す
                if (p.ExitCode != 0 && lines.Count == 0 && !(exe == "rg" && p.ExitCode == 1)) return null;
            }
            return lines;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private static List<string> Walk(string project)
    {
        var lines = new List<string>();
        var stack = new Stack<string>();
        stack.Push(project);
        string root = project.TrimEnd('\\', '/') + "\\";
        while (stack.Count > 0 && lines.Count < MaxProjectFiles)
        {
            string dir = stack.Pop();
            try
            {
                foreach (string f in Directory.GetFiles(dir)) lines.Add(f.Substring(root.Length));
                foreach (string d in Directory.GetDirectories(dir))
                {
                    string n = Path.GetFileName(d);
                    if (n == ".git" || n == "node_modules") continue;
                    stack.Push(d);
                }
            }
            catch (UnauthorizedAccessException) { }
            catch (IOException) { }
        }
        return lines;
    }

    private static string NoteDir()
    {
        string cfg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dotfiles.json");
        if (!File.Exists(cfg)) return null;
        string vault = JsonString(File.ReadAllText(cfg, Encoding.UTF8), "vault");
        if (string.IsNullOrEmpty(vault)) return null;
        string note = Path.GetFullPath(Path.Combine(vault, "note"));
        return Directory.Exists(note) ? note : null;
    }

    private static bool IsUnder(string path, string dir)
    {
        string p = Path.GetFullPath(path).TrimEnd('\\') + "\\";
        string d = Path.GetFullPath(dir).TrimEnd('\\') + "\\";
        return p.StartsWith(d, StringComparison.OrdinalIgnoreCase);
    }

    // 平らな JSON から文字列の値を 1 つ取る（入れ子は見ない。この 2 か所の入力にはそれで足りる）
    private static string JsonString(string json, string key)
    {
        Match m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        if (!m.Success) return null;
        string s = m.Groups[1].Value;
        var sb = new StringBuilder(s.Length);
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            if (c != '\\' || i + 1 >= s.Length) { sb.Append(c); continue; }
            char n = s[++i];
            switch (n)
            {
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'u':
                    if (i + 4 < s.Length)
                    {
                        sb.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16));
                        i += 4;
                    }
                    break;
                default: sb.Append(n); break;
            }
        }
        return sb.ToString();
    }
}
