// ime.exe — 今フォーカスされているウィンドウの IME を ON/OFF する・状態を返す。
//
//   ime      … 状態を標準出力に出す（0=OFF・1=ON）
//   ime 0    … OFF にする
//   ime 1    … ON にする
//   終了コード 0=成功・1=引数が変・2=相手に IME が無い・3=応答が無い
//
// 何のためにあるか: Obsidian の Vim モードで、ノーマルモードに戻った時に IME を切るため。
// Obsidian 側のプラグイン（Vim IM Select）が「状態を取るコマンド」と「切り替えるコマンド」を
// 外部コマンドとして呼ぶ仕組みなので、その受け皿が必要になる。
// nvim は同じことを Lua の FFI で直接やる（nvim/lua/config/ime.lua）＝こちらは呼ばない。
//
// 仕組み: IME の ON/OFF はウィンドウごとに持たれていて、そのウィンドウのスレッドが持つ
// 「既定の IME ウィンドウ」へ WM_IME_CONTROL を送ると外から変えられる（zenhan.exe と同じ手）。
// 2026-10-05 に Windows 11 (26300) / Google 日本語入力で、Obsidian と WezTerm の両方で実測。
//
// ビルドは install.ps1 がやる（Windows 同梱の csc.exe。SDK や Visual Studio は要らない）:
//   csc /target:winexe /out:tools\bin\ime.exe tools\ime\Ime.cs
// winexe にしているのは、コンソール窓を一瞬も出さないため。標準出力は、呼び出し側が
// 受け取る形（パイプ・リダイレクト）ならそのまま流れる。

using System;
using System.Runtime.InteropServices;

internal static class Ime
{
    private const uint WM_IME_CONTROL = 0x0283;
    private const int IMC_GETOPENSTATUS = 0x0005;
    private const int IMC_SETOPENSTATUS = 0x0006;
    private const uint SMTO_ABORTIFHUNG = 0x0002;
    private const uint TIMEOUT_MS = 300;

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("imm32.dll")]
    private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam,
                                                     uint flags, uint timeout, out IntPtr result);

    private static int Main(string[] args)
    {
        IntPtr ime = ImmGetDefaultIMEWnd(GetForegroundWindow());
        if (ime == IntPtr.Zero)
        {
            return 2; // IME を持たないウィンドウ（前面に何も無い時もここ）
        }

        IntPtr result;
        if (args.Length == 0)
        {
            if (SendMessageTimeoutW(ime, WM_IME_CONTROL, (IntPtr)IMC_GETOPENSTATUS, IntPtr.Zero,
                                    SMTO_ABORTIFHUNG, TIMEOUT_MS, out result) == IntPtr.Zero)
            {
                return 3;
            }
            Console.Out.Write(result.ToInt64() == 0 ? "0" : "1");
            return 0;
        }

        int want;
        if (!int.TryParse(args[0], out want) || (want != 0 && want != 1))
        {
            return 1;
        }
        if (SendMessageTimeoutW(ime, WM_IME_CONTROL, (IntPtr)IMC_SETOPENSTATUS, (IntPtr)want,
                                SMTO_ABORTIFHUNG, TIMEOUT_MS, out result) == IntPtr.Zero)
        {
            return 3;
        }
        return 0;
    }
}
