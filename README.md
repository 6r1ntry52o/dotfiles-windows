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
    │   │   └── autocmds.lua 自動コマンドの上書き
    │   └── plugins/         自分で足す・変えるプラグイン
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

## 外す

- `~/.wezterm.lua` を消す（退避した `.bak-*` があれば戻す）
- `$PROFILE` と WSL の `~/.bashrc`・`~/.zshrc` から、末尾が `# managed by dotfiles-windows/install.ps1` の行を消す
- `cmd /c rmdir %LOCALAPPDATA%\nvim` で junction だけ外す（リポの `nvim/` は残る。退避した `nvim.bak-*` があれば戻す）。プラグインも消すなら `%LOCALAPPDATA%\nvim-data` を消す
