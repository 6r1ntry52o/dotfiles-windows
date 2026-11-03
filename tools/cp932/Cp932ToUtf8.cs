// cp932-to-utf8.exe — 標準入力を行ごとに見て、UTF-8 として正しくない行を CP932 から UTF-8 に直す。
// UTF-8 の行と ASCII（色のエスケープ）はそのまま通す＝UTF-8 と CP932 が混ざった差分でもよい。
//
// 何のためにあるか: lazygit の差分表示の文字化けを直すため（git.diffRenderers の command に
// 指定する・設定は install.ps1 が書く）。git の textconv は使わない: lazygit の行ステージは
// `git diff` の結果をそのまま `git apply` するので、textconv で UTF-8 にした行が
// CP932 のファイルの index に混ざる。diffRenderers は表示にしか使われない
// （ステージ用の差分はこれを通らない＝2026-11-03 に lazygit 0.65.1 で実測・index は CP932 のまま）。
//
// ビルドは install.ps1 がやる（Windows 同梱の csc.exe）:
//   csc /optimize /out:tools\bin\cp932-to-utf8.exe tools\cp932\Cp932ToUtf8.cs

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class Cp932ToUtf8
{
    [DllImport("kernel32.dll")]
    private static extern bool SetConsoleOutputCP(uint codePage);

    private static bool IsUtf8(byte[] b, int start, int end)
    {
        int i = start;
        while (i < end)
        {
            byte c = b[i];
            int len;
            if (c < 0x80) len = 1;
            else if (c >= 0xC2 && c <= 0xDF) len = 2;
            else if (c >= 0xE0 && c <= 0xEF) len = 3;
            else if (c >= 0xF0 && c <= 0xF4) len = 4;
            else return false;
            if (i + len > end) return false;
            for (int j = i + 1; j < i + len; j++)
            {
                if (b[j] < 0x80 || b[j] > 0xBF) return false;
            }
            i += len;
        }
        return true;
    }

    private static void WriteLine(Stream output, Encoding cp932, byte[] b, int start, int end)
    {
        if (IsUtf8(b, start, end))
        {
            output.Write(b, start, end - start);
            return;
        }
        byte[] converted = Encoding.UTF8.GetBytes(cp932.GetString(b, start, end - start));
        output.Write(converted, 0, converted.Length);
    }

    private static int Main()
    {
        // lazygit は pty の中で動かすので、出力先はコンソール。日本語の Windows では既定が CP932 で、
        // UTF-8 のまま書くとコンソールが読み違える。
        SetConsoleOutputCP(65001);
        Encoding cp932 = Encoding.GetEncoding(932);
        try
        {
            using (Stream input = Console.OpenStandardInput())
            using (Stream output = Console.OpenStandardOutput())
            {
                byte[] buf = new byte[65536];
                int have = 0;
                int n;
                while ((n = input.Read(buf, have, buf.Length - have)) > 0)
                {
                    have += n;
                    int start = 0;
                    int nl;
                    while ((nl = Array.IndexOf(buf, (byte)'\n', start, have - start)) >= 0)
                    {
                        WriteLine(output, cp932, buf, start, nl + 1);
                        start = nl + 1;
                    }
                    Buffer.BlockCopy(buf, start, buf, 0, have - start);
                    have -= start;
                    if (have == buf.Length)
                    {
                        Array.Resize(ref buf, buf.Length * 2); // 改行の無い長い行
                    }
                    output.Flush();
                }
                WriteLine(output, cp932, buf, 0, have);
            }
        }
        catch (IOException)
        {
            // 読み手が先に閉じた（lazygit で別のファイルに移った時）。エラーではない。
        }
        return 0;
    }
}
