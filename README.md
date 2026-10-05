# dotfiles-windows

Windows 用の設定置き場。WezTerm・PowerShell・WSL のシェル・Neovim（LazyVim）。Mac 用は別リポ [`dotfiles`](https://github.com/6r1ntry52o/dotfiles)。

## 新しい PC に入れる

```powershell
git clone https://github.com/6r1ntry52o/dotfiles-windows.git $HOME\dev_repository\dotfiles-windows
powershell -ExecutionPolicy Bypass -File $HOME\dev_repository\dotfiles-windows\install.ps1
```

終わったら新しいタブを開き、`nvim` を一度起動して待つ（LazyVim が `nvim/lazy-lock.json` の版でプラグインを入れる。パーサーのビルドもここで走る）。確認は `:LazyHealth`。

`install.ps1` がすること（何度流してもよい）:

1. winget で次を入れる（入っていれば何もしない。`-SkipPackages` で飛ばせる）
   - WezTerm・PowerShell 7・Neovim
   - LazyVim が使うもの: ripgrep（`rg`）・fd・fzf・lazygit・zig（C コンパイラ）・tree-sitter-cli（後ろ 2 つはパーサーのビルド用）
2. `~/.wezterm.lua` に、このリポの `wezterm/wezterm.lua` を読み込む 5 行のスタブを書く
   - 既存の `~/.wezterm.lua` が自分の物なら `.bak-日時` に退避してから上書き
   - シンボリックリンクではないので管理者権限は不要。clone 先はどこでもよい（移動したら再実行）
3. PowerShell 7 の `$PROFILE` に、このリポの `powershell/profile.ps1` を読み込む 1 行を足す（既存の中身はそのまま）
   - Windows PowerShell 5.1 は、実行ポリシーがスクリプトを許可している時だけ同じ 1 行を足す（既定の Restricted では飛ばす）
4. WSL があれば、各ディストリ（`docker-desktop` 以外）の `~/.bashrc` に `wsl/osc7.sh` を読み込む 1 行を足す
   - zsh が入っているディストリでは `~/.zshrc` にも `wsl/osc7.zsh` を読み込む 1 行を足す（zsh 自体は入れない。`sudo apt install zsh` → `chsh -s /usr/bin/zsh`）
5. `%LOCALAPPDATA%\nvim` を、このリポの `nvim/` を指す junction にする
   - 既存の `%LOCALAPPDATA%\nvim` が実フォルダなら `nvim.bak-日時` に改名して退避する
   - junction なので管理者権限は不要。clone 先を移動したら再実行（古い junction は張り替える）
   - WezTerm と違ってスタブにしないのは、lazy.nvim が `lazy-lock.json` を設定フォルダへ書くため（フォルダごとリポに置かないと版を追跡できない）
6. `tools/ime/Ime.cs` を `tools/bin/ime.exe` にビルドする（Windows 同梱の `csc.exe`。SDK も Visual Studio も要らない）
   - 外から IME を切る小物。Obsidian の Vim モードが呼ぶ（下の「日本語入力」）。Neovim は同じことを Lua でやるのでこれは使わない
   - Google 日本語入力の設定（`google-ime/`）は `install.ps1` では戻さない＝新しい PC で `google-ime\Restore-GoogleIme.ps1` を手で流す（既存の設定を黙って上書きしないため）

## 設定を変える・同期する

- 編集するのは `wezterm/*.lua`。保存すると WezTerm が自動で再読み込みする（手動は `Ctrl+Shift+R`）
- 他の PC へは `git push` → 向こうで `git pull` だけ
- Neovim は `nvim/lua/config/*.lua`（オプション・キー）と `nvim/lua/plugins/*.lua`（プラグイン）を編集する。`%LOCALAPPDATA%\nvim` から開いても同じファイル
  - プラグインを更新（`:Lazy update`）すると `nvim/lazy-lock.json` が変わるので、それも commit する
  - 他の PC では `git pull` のあと `:Lazy restore`（lock の版に揃える）
  - `:LazyExtras` で足した機能は `nvim/lazyvim.json` に記録される（これも commit する）

## 構成

### リポの中身

```
dotfiles-windows/
├── install.ps1              セットアップ（winget で導入し、下の各設定を PC へ繋ぐ）
├── README.md
├── wezterm/
│   ├── wezterm.lua          本体（見た目・既定シェル・タブ）
│   └── keybinds.lua         キーバインド
├── powershell/
│   └── profile.ps1          PowerShell のプロファイル（現在地の通知・vi 系のエイリアス）
├── tools/
│   ├── Survey-Encoding.ps1          文字コードの棚卸し（読み取り専用・集計だけ画面に出す）
│   ├── Install-MsbuildExtractor.ps1 compile_commands.json を作る抽出ツールを入れる（下の「C/C++」）
│   ├── ime/Ime.cs                   外から IME を切る小物のソース（install.ps1 がビルド）
│   └── bin/                         ビルド結果（git 管理外・ime.exe）
├── google-ime/                 Google 日本語入力の設定（下の「日本語入力」）
│   ├── config1.db                   設定の実体（復元に使う）
│   ├── keymap.txt                   カスタムキーマップ（F13=OFF・F14=ON）
│   ├── settings.md                  既定と違う所の説明
│   ├── Export-GoogleIme.ps1         今のPC → リポ
│   └── Restore-GoogleIme.ps1        リポ → 新しいPC
├── wsl/
│   ├── install.sh           WSL 側のセットアップ（install.ps1 から呼ばれる）
│   ├── osc7.sh              bash 用（現在地の通知。末尾で aliases.sh を読む）
│   ├── osc7.zsh             zsh 用（現在地の通知。末尾で aliases.sh を読む）
│   └── aliases.sh           bash・zsh 共通のエイリアス
└── nvim/                    Neovim（LazyVim/starter が元）
    ├── init.lua             入口（lua/config/lazy.lua を読むだけ）
    ├── lua/
    │   ├── config/
    │   │   ├── lazy.lua     起動（lazy.nvim と LazyVim を読み込む）
    │   │   ├── options.lua  オプションの上書き
    │   │   ├── keymaps.lua  キーの上書き
    │   │   ├── autocmds.lua 自動コマンドの上書き
    │   │   ├── encoding.lua 混在ツリーを検索するための小物（下の「文字コード」）
    │   │   └── ime.lua      INSERT 以外では IME を OFF にする（下の「日本語入力」）
    │   └── plugins/         自分で足す・変えるプラグイン
    │       ├── encoding.lua 文字コードの表示と <leader>sJ
    │       ├── obsidian.lua Obsidian vault（:Obsidian open・<leader>fo から呼ばれる）
    │       └── clangd.lua   C/C++ の :CompileCommands（下の「C/C++」）
    ├── lazy-lock.json       プラグインの版の固定（lazy.nvim が書く）
    ├── lazyvim.json         LazyVim の状態（入れた extras・LazyVim が書く）
    ├── stylua.toml          Lua の整形設定
    ├── .neoconf.json        neoconf の設定
    └── LICENSE              LazyVim/starter の Apache-2.0
```

### PC 側とのつながり

`install.ps1` が作るのは右向きの矢印だけ。設定の実体はすべてリポにある。

```
PC 側（install.ps1 が作る・書き足す）                  リポ側（実体）
─────────────────────────────────────────────────────────────────────────
Windows
├── ~/.wezterm.lua                    ──読み込む──▶ wezterm/wezterm.lua
│   （5 行のスタブ）                                 └─▶ wezterm/keybinds.lua
├── ~/Documents/PowerShell/
│   └── Microsoft.PowerShell_profile.ps1
│       （1 行を追記）                ──読み込む──▶ powershell/profile.ps1
├── %LOCALAPPDATA%/nvim               ──junction──▶ nvim/
└── %LOCALAPPDATA%/nvim-data          リポの外（プラグイン本体・パーサー。消しても入り直す）

WSL（docker-desktop 以外の各ディストリ）
├── ~/.bashrc （1 行を追記）          ──読み込む──▶ wsl/osc7.sh  ─┐
└── ~/.zshrc  （1 行を追記・zsh 有時）──読み込む──▶ wsl/osc7.zsh ─┴─▶ wsl/aliases.sh
```

### 動かしたときの重なり

```
WezTerm（wezterm/*.lua）
├── タブ / ペイン
│   ├── PowerShell 7（既定・powershell/profile.ps1）
│   │   └── vi / vim / view ─▶ Neovim + LazyVim（nvim/）
│   ├── WSL の bash・zsh（Ctrl+Shift+U・wsl/*.sh）
│   │   └── vi / vim / view ─▶ WSL 側の Neovim（入れていれば。nvim/ の設定は繋がない）
│   └── Git Bash・PowerShell 5.1（Ctrl+Shift+L のランチャーから）
└── Leader = Ctrl+Q（WezTerm のキー）／Neovim の <leader> = Space
```

- Neovim: LazyVim（https://www.lazyvim.org ・`nvim/` は LazyVim/starter が元。`nvim/LICENSE` はその Apache-2.0）。`<leader>` はスペース。押して待つとキー一覧が出る
  - プラグイン本体とパーサーは `%LOCALAPPDATA%\nvim-data` に入る（リポの外・消しても次の起動で入り直す）
  - アイコンは WezTerm 同梱の Nerd Font Symbols で出る。他のターミナルで開くなら Nerd Font を入れる
  - WSL 側の Neovim にはこの設定を繋がない（Windows の Neovim だけ）

- エディタ: `vi`・`vim` は Neovim、`view` は `nvim -R`（読み取り専用）で開く。Neovim が入っている環境だけ有効（Windows は `install.ps1` が入れる。WSL は `sudo apt install neovim`・このリポでは入れない）。対応は PowerShell と WSL の bash・zsh。Git Bash は対象外

- 作業場: 起動時は Windows のホーム、`Ctrl+Shift+U` の WSL は Linux のホーム。新規タブ・分割は今いるペインの場所を引き継ぐ
  - 引き継ぎはシェルがプロンプトのたびに現在地を WezTerm へ通知（OSC 7）して実現している。対応は PowerShell 7 と WSL の bash・zsh。Git Bash と、プロファイルを読まない PowerShell 5.1 は常にホームで開く
- 既定シェル: PowerShell 7（無ければ Windows PowerShell 5.1 に落ちる）。ランチャーに 5.1・Git Bash・WSL も出る
- WSL: ディストリは自動検出（`docker-desktop` 以外の先頭を `Ctrl+Shift+U` に割り当て）。WSL のタブ内で分割・新規タブをすると同じ WSL で開く。WSL 自体の導入は `wsl --install`（このリポでは入れない）
- フォント: HackGen Console（https://github.com/yuru7/HackGen ・手動で入れる。未導入の PC では同梱の JetBrains Mono に落ちる）
- タブ: 丸みのない四角形（retro 型）。表示はプログラム名だけで 16 文字まで。アクティブ＝`#82aaff`（LazyVim のタイトルと同じ青・文字は濃色）。×ボタンは無い（閉じるのは `Ctrl+Shift+W`）
- タイトルバーなし: 終了は `Alt+F4`、移動はタブバーの空き部分をドラッグ

## キーバインド

既定のキーは無効化してある。Leader = `Ctrl+Q`（2 秒以内に次のキー）。

| キー | 動作 |
|---|---|
| `Ctrl+Shift+T` / `Ctrl+Shift+W` | タブを開く / 閉じる |
| `Ctrl+Shift+U` | WSL を新しいタブで開く（Linux のホームで始まる） |
| `Ctrl+Shift+L` | ランチャー（PowerShell・Git Bash・WSL から選んで開く） |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | 次 / 前のタブ |
| `Alt+1`〜`8` / `Alt+9` | N 番目 / 最後のタブ |
| `Leader {` / `Leader }` | タブを左 / 右へ移動 |
| `Leader d` / `Leader r` | 上下 / 左右に分割 |
| `Leader h/j/k/l` | ペイン移動 |
| `Leader x` / `Leader z` | ペインを閉じる / ズーム |
| `Leader s` → `h/j/k/l` | ペインのサイズ変更（`Enter` / `Esc` で抜ける） |
| `Ctrl+Shift+[` | ペイン選択 |
| `Leader w` / `Leader W` / `Leader $` | ワークスペース切替 / 新規 / 改名 |
| `Ctrl+Shift+C` / `Ctrl+Shift+V` | コピー / 貼り付け |
| `Leader [` | コピーモード（vim 風・`y` でコピー・`q` で抜ける） |
| `Ctrl+Shift+P` | コマンドパレット（ランチャーもここから） |
| `Ctrl+Shift+R` | 設定の再読み込み |
| `Ctrl +` / `Ctrl -` / `Ctrl 0` | 文字サイズ 拡大 / 縮小 / リセット |
| `Alt+Enter` | フルスクリーン |

Mac 版との違い: `Cmd+T/W/C/V` → `Ctrl+Shift+T/W/C/V`、`Cmd+数字` → `Alt+数字`。

## 日本語入力（IME）

IME は Google 日本語入力。**ON/OFF はトグルを使わず、F13 = OFF・F14 = ON**（キーボード側の QMK レイヤから送る。macOS の「英数 / かな」と同じ考え方＝押した方向が決まっているので、今どちらかを覚えていなくても外さない）。

### Neovim: INSERT 以外では必ず OFF

`nvim/lua/config/ime.lua`。INSERT を抜けた時・コマンドラインを抜けた時・`:terminal` の入力モードを抜けた時・起動時・他のアプリから戻った時（INSERT 中以外）に IME を切る。

- 外部コマンドは呼ばない。LuaJIT の FFI で `GetForegroundWindow` → `ImmGetDefaultIMEWnd` → `WM_IME_CONTROL` を直接叩く（Esc のたびに exe を起動しない）
- フォーカスを失っている間は何もしない（前面は別アプリ＝そちらの IME を消さないため）
- Windows の Neovim だけ。WSL・Linux 側の Neovim では何もしない（あちらの IME は X/Wayland 側の持ち物）
- 効いているかの確認は `:ImeState`（0=OFF・1=ON）
- INSERT に戻った時に IME を元へ戻すことはしない。「INSERT 以外は必ず OFF」が目的で、日本語を打つ時は F14 を押す

### Google 日本語入力の設定

| ファイル | 何 |
|---|---|
| `google-ime/config1.db` | 設定の実体。復元に使う |
| `google-ime/keymap.txt` | カスタムキーマップ。GUI の「キー設定の選択 → 編集 → インポート」でも読める形 |
| `google-ime/settings.md` | 既定と違う所の説明（カスタムキーマップ・絵文字変換 ON） |
| `google-ime/Export-GoogleIme.ps1` | 今のPC → リポ（GUI で設定を変えた後に流す） |
| `google-ime/Restore-GoogleIme.ps1` | リポ → このPC（新しい PC のセットアップ用。今の設定は `.bak-日時` に退避する） |

ユーザー辞書と学習履歴（`history.db`・`segment.db` ほか）は入れない＝個人の入力内容そのもので、公開リポジトリに置くものではない。新しい PC では学習し直す。

### Obsidian（Vim モード）

Obsidian は外部コマンド経由でしか IME を触れないので、プラグインを 1 つ入れる（手作業）:

1. コミュニティプラグイン **Vim IM Select**（`alonelur/vim-im-select-obsidian`）を入れて有効化する
2. そのプラグインの設定で Windows 用の 3 項目を埋める
   - Windows Default IM: `0`
   - Obtaining Command for Windows: `C:\Users\6r1nt\source\dotfiles-windows\tools\bin\ime.exe`
   - Switching Command for Windows: `C:\Users\6r1nt\source\dotfiles-windows\tools\bin\ime.exe {im}`
   - clone 先を変えたらこのパスも直す
3. Obsidian を再起動する

`ime.exe` は `tools/ime/Ime.cs` を `install.ps1` がビルドしたもの（引数なしで状態を出し、`0`/`1` で切り替える）。`winexe` なのでコンソール窓は一瞬も出ない。

## 文字コード（Shift_JIS が混ざったプロジェクト）

会社のソースは CP932（Shift_JIS）が主で、UTF-8 のファイルも混ざっている。Neovim の既定では
`fileencodings` の最後にある `latin1` がどんなバイト列でも「成功」してしまうので、BOM なしの
CP932 は必ず化ける。`cp932` を `latin1` の前に入れてあるのがその対策（`nvim/lua/config/options.lua`）。

| 困る場面 | 手段 |
|---|---|
| 開くと化ける | 自動で判定する（`ucs-bom` → `utf-8` → `cp932`）。外した時だけ `:EncOpen cp932`（`euc-jp` なども補完に出る） |
| 今どれで開いているか分からない | ステータスライン右に出る（`cp932`・`BOM`・`CR`）。UTF-8 かつ BOM なしの時は何も出さない |
| 日本語で grep が当たらない | `<leader>sJ`＝UTF-8 と CP932 を 1 回で検索する。既定の `<leader>sg` は UTF-8 のファイルにしか当たらない |
| 保存で文字コードが変わらないか不安 | 読んだ文字コードのまま書き戻る。変えたい時だけ `:EncToUtf8` / `:EncToSjis` |
| 新しく作ったファイルを周りに合わせたい | `:EncToSjis`（既定は UTF-8。これで混在を増やさない） |
| `:make` や quickfix の出力が化ける | その場で `:set makeencoding=char`（常時入れると `:grep` の出力が逆に化けるので入れていない） |
| プロジェクト全体の内訳を知りたい | `pwsh -File tools\Survey-Encoding.ps1 -Path <フォルダ>`（読み取り専用。パスを含む明細は `-DetailOut` を付けた時だけローカルに書く） |

`<leader>sJ` の仕組み: ripgrep は 1 回の実行でファイルごとに文字コードを見分けられない
（`--encoding sjis` は全ファイルを CP932 扱い、既定は BOM しか見ない）。そこで変換はさせず、
検索語を「UTF-8 のバイト列 | CP932 のバイト列」の 2 択に展開して、バイト列として照合させている。
UTF-8・UTF-8 BOM・UTF-16・CP932 が 1 回で当たる。結果の行と列番号は表示前に UTF-8 へ直す
（`nvim/lua/config/encoding.lua`）。`sg` と分けてあるのは、この方式では `--no-unicode` が効いて
正規表現の意味が少し変わるため（`.` が 1 バイト・`\w` と大文字小文字の無視が ASCII だけ）。

置換（`<leader>sr`・grug-far）の検索も ripgrep なので、CP932 のファイルは日本語では当たらない。
CP932 のファイルを直す時は、そのファイルを開いて `:%s` でやる（保存時に CP932 のまま書き戻る）。

## C/C++（Visual Studio のソリューション）

LazyVim の `lang.clangd` extra を有効にしてある（`nvim/lazyvim.json`）。clangd 本体は mason が入れる。
インクルードパスの手当ては要らない — clangd が MSVC と Windows SDK を自分で見つける
（実測: `std::cout` から `BuildTools\VC\Tools\MSVC\14.44.35207\include\iostream` へ飛ぶ。`clangd --check` も 0 errors）。

| 困る場面 | 手段 |
|---|---|
| 定義に飛びたい | `gd`（宣言 `gD`・参照 `gr`・実装 `gI`・型定義 `gy`） |
| ソースとヘッダを行き来したい | `<leader>ch` |
| 別の `.cpp` にある定義が参照検索に出ない | `:CompileCommands`。そのファイルの上にある `.sln`（無ければ `.vcxproj`）から `compile_commands.json` を作る |
| プロジェクト固有の `/I` や `/D` が効いていない | 同じく `:CompileCommands`。これが無いと clangd は「開いているファイルの翻訳単位」しか見ない |
| 抽出ツールが入っていない | `pwsh -File tools\Install-MsbuildExtractor.ps1`（SHA256 を検証して `%LOCALAPPDATA%\msbuild-extractor\` に置く） |
| LSP が動いているか確かめたい | `<leader>cl`（`:checkhealth` でも見える） |

`:CompileCommands` の仕組み: MSBuild は `compile_commands.json` を出さないので、Microsoft の抽出ツール
（[msbuild-extractor-sample](https://github.com/microsoft/msbuild-extractor-sample)）を呼ぶ。design-time 評価なのでビルドは走らない。
構成（`Debug|x64` など）は `.sln` の `SolutionConfigurationPlatforms` の先頭を読む — 決め打ちにすると
違う構成のフラグを掴む。リポに `msbuild-extractor.json` があればそれに従う（`-c`/`-a` は渡さない）。
出力は `<ルート>\build\compile_commands.json`。clangd は編集中のファイルの親ディレクトリとその `build/` を
順に探すので、置き場所の設定は要らない。ツールは `PATH` → `<プロジェクト>\.tools` → `%LOCALAPPDATA%\msbuild-extractor` の順に探す。

実測（2026-10-05・テスト用の .sln で確認）: 生成前は別 TU の定義が参照に出ず（`add` の参照 1 件）、
生成後は 3 件（ヘッダの宣言・`.cpp` の定義・呼び出し）。`AdditionalIncludeDirectories` に入れた
`include\extra.h` も生成後に解決する。

罠: 抽出ツールは self-contained の exe で、VS 側の MSBuild を見つけられないと .NET SDK 探索に落ち、
`hostfxr.dll` を解決できず `DllNotFoundException` で死ぬ（`--vs-path` も `--msbuild-path` も効かない。
引数の処理より前に走るため）。dotnet の `hostfxr.dll` を exe の隣に置くと通る＝導入スクリプトがやっている。

## 外す

- `~/.wezterm.lua` を消す（退避した `.bak-*` があれば戻す）
- `$PROFILE` と WSL の `~/.bashrc`・`~/.zshrc` から、末尾が `# managed by dotfiles-windows/install.ps1` の行を消す
- `cmd /c rmdir %LOCALAPPDATA%\nvim` で junction だけ外す（リポの `nvim/` は残る。退避した `nvim.bak-*` があれば戻す）。プラグインも消すなら `%LOCALAPPDATA%\nvim-data` を消す
- Google 日本語入力の設定を戻すなら `config1.db.bak-*` を元の名前に戻す（`Restore-GoogleIme.ps1` が退避したもの）。GUI だけで戻すならキー設定の選択を「MS-IME」にする
- Obsidian の Vim IM Select を無効化する。`tools/bin/` は消してよい（`install.ps1` が作り直す）
