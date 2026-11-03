# dotfiles-windows

Windows 用の設定置き場。WezTerm・PowerShell・WSL のシェル・Neovim（LazyVim）・AI エージェント（Claude Code・GitHub Copilot CLI）。Mac 用は別リポ [`dotfiles`](https://github.com/6r1ntry52o/dotfiles)。

## セットアップ

clone 先はどこでもよい。

```powershell
git clone https://github.com/6r1ntry52o/dotfiles-windows.git
powershell -ExecutionPolicy Bypass -File .\dotfiles-windows\install.ps1
```

終わったら新しいタブを開き、`nvim` を一度起動して待つ（プラグインとパーサーが入る。確認は `:LazyHealth`）。

`install.ps1` は何度流してもよい。clone 先を移したら流し直す。設定を最新にする時も流すだけ（0 で clone が最新になる）。やること:

| # | 内容 |
|---|---|
| 0 | clone を最新にする（今のブランチを `git pull --ff-only`。手元のコミットや変更が邪魔で進められない時は警告して、今の中身で続ける。`install.ps1` 自身が変わったら新しい方で流し直す。`-NoPull` で飛ばせる） |
| 1 | winget で WezTerm・Neovim・ripgrep・fd・fzf・lazygit・zig・tree-sitter-cli を入れる。PowerShell 7 は MSI 版（`C:\Program Files\PowerShell\7`）があるかを確かめる |
| 2 | フォント HackGen Console NF を入れる |
| 2b | C/C++ 用に lazymsbuild と msbuild-extractor-sample を入れる（lazymsbuild は実行のたびに最新のリリースへ上げる。msbuild-extractor-sample の版は `tools/` のスクリプトで固定する。どちらも SHA256 を確かめる。lazymsbuild は `%LOCALAPPDATA%\Programs\lazymsbuild` に置いてユーザーの PATH に足す。1〜2b は `-SkipPackages` で飛ばせる） |
| 3 | `~/.wezterm.lua` に `wezterm/wezterm.lua` を読むスタブを書く（既存は `.bak-日時` に退避） |
| 4 | PowerShell の `$PROFILE` に `powershell/profile.ps1` を読む 1 行を足す。5.1 の実行ポリシーが未設定なら CurrentUser を RemoteSigned にする |
| 5 | WSL の `~/.bashrc`・`~/.zshrc` に `wsl/osc7.*` を読む 1 行を足す（`docker-desktop` 以外） |
| 6 | `%LOCALAPPDATA%\nvim` を `nvim/` への junction にする（既存は `nvim.bak-日時` に退避） |
| 7 | `tools/bin/ime.exe` をビルドする（Obsidian 用） |
| 7b | `tools/bin/cp932-to-utf8.exe` をビルドし、`%LOCALAPPDATA%\lazygit\config.yml` に差分の表示フィルタとして書く（下の「文字コード」。自分で書いた `config.yml` があれば触らず、足す内容を警告で出す。clone 先を移したら流し直す） |
| 8 | `~/.dotfiles.json` を、無ければ作る（下の「PC ごとの設定」） |
| 8b | `obsidian/snippets/*.css`（note/ のチェックボックスの状態の見た目）を vault の `.obsidian/snippets` に写し、Obsidian が開いていれば有効にする（下の「Obsidian」） |
| 9 | AI エージェント（Claude Code・GitHub Copilot CLI）が入っている PC で、スキルを見せ、エディタと同じ言語サーバを使えるようにする。vault がある PC では、どのリポから起動しても vault を読めるようにし、note/ を守るフックをつなぐ（下の「AI エージェント」。プラグインと rust-analyzer の取得は `-SkipPackages` で飛ばせる） |

管理者権限は要らない。次は `install.ps1` がやらないので、要る PC だけ手で行う。

| 何 | 手順 |
|---|---|
| PowerShell 7（MSI 版） | **管理者**で `winget install --id Microsoft.PowerShell -e --source winget --scope machine`。Store 版（MSIX）が入っていたら `Get-AppxPackage Microsoft.PowerShell \| Remove-AppxPackage` で外す。Store 版は WindowsApps のエイリアスで、Neovim から起動できない＝`<leader>ft` が 5.1 に落ちて `claude` などの `.ps1` が実行ポリシーで止まる |
| Google 日本語入力の設定 | `google-ime\Restore-GoogleIme.ps1` を流す（今の設定は `.bak-日時` に退避） |
| US 配列キーボード | **管理者**で `keychron\Set-UsPhysicalLayout.ps1` を流して再起動（`-Show` で確認・`-Revert` で戻す） |
| Obsidian の IME 連携 | 下の「Obsidian」 |

## PC ごとの設定（`~/.dotfiles.json`）

PC ごとに変わる値はホームの `~/.dotfiles.json` 1 枚に集める。リポには PC 固有のパスを書かない。

```json
{
  "vault": "C:/Users/<you>/core",
  "vault_ai_dir": "nexus/fields",
  "wezterm": { "font_size": 12.0 }
}
```

| キー | 何に使う | 無いとき |
|---|---|---|
| `vault` | Obsidian vault の場所（Neovim・PowerShell・AI エージェントが読む） | Obsidian 関連の機能を読み込まない |
| `vault_ai_dir` | AI エージェントがまとめや TODO を書く vault 内のフォルダ（vault からの相対。分野ごとに `<分野>.md`）。PC ごとに決める | エージェントは vault に書く前に置き場を聞く |
| `wezterm.font_size` | 文字の大きさ | 12.0 |

### 別の PC で使う

このファイルは他の PC からコピーしない（中身がその PC のパスなので）。`install.ps1` が PC ごとに作る。

1. その PC の Obsidian で vault を一度開く（置き場所はどこでもよい）
2. `install.ps1` を流す。`created ~/.dotfiles.json (vault = ...)` と出れば完了
3. nvim と PowerShell を開き直す

`vault` は Obsidian が覚えている vault から選ぶ（今開いているもの → 最後に開いたもの）。Obsidian を起動したことのない PC では `~/core`・`~/vault`・`~/Obsidian` を見る。

手で書くのは次の場合だけ。`"vault"` の 1 行を `/` 区切りのパスに直す。

- 検出できなかった（空で作られる）・違う vault が入った
- その PC にすでに `~/.dotfiles.json` がある（`install.ps1` は既存のファイルを触らない）

## 使い方

### WezTerm

既定シェルは PowerShell 7。新規タブ・分割は今いるペインの場所を引き継ぐ（PowerShell 7 と WSL の bash・zsh）。タイトルバーは無い＝終了は `Alt+F4`、移動はタブバーの空きをドラッグ。

既定のキーは無効化してある。Leader = `Ctrl+Q`（2 秒以内に次のキー）。

| キー | 動作 |
|---|---|
| `Ctrl+Shift+T` / `Ctrl+Shift+W` | タブを開く / 閉じる |
| `Ctrl+Shift+U` | WSL を新しいタブで開く |
| `Ctrl+Shift+L` | ランチャー（PowerShell・Git Bash・WSL から選ぶ） |
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
| `Ctrl+Shift+P` | コマンドパレット |
| `Ctrl+Shift+R` | 設定の再読み込み |
| `Ctrl +`（`Ctrl+Shift+=`・`Ctrl+=`・テンキー）/ `Ctrl -` / `Ctrl 0` | 文字サイズ 拡大 / 縮小 / リセット（ウィンドウの大きさは変えない） |
| `Alt+Enter` | フルスクリーン |

### シェル

| コマンド | 動作 |
|---|---|
| `vi` / `vim` | Neovim を開く |
| `view` | 読み取り専用で開く（`nvim -R`） |
| `vault` | Obsidian vault へ `cd`（PowerShell のみ。パスは `$env:DOTFILES_VAULT`） |

`vi` 系は PowerShell と WSL の bash・zsh で効く。WSL 側の Neovim と zsh はこのリポでは入れない。

### Neovim

LazyVim（https://www.lazyvim.org）。`<leader>` はスペースで、押して待つとキー一覧が出る。下は自分で足したもの。

| キー / コマンド | 動作 |
|---|---|
| `<leader>fo` | 今のファイルを既定アプリで開く（vault 内のノートは Obsidian） |
| `<leader>fw` | 今のファイルをエクスプローラで選択状態にして開く |
| `<leader>fy` | 今のファイルの絶対パスをコピー |
| `<leader>sJ` | UTF-8 と CP932 を 1 回で検索（下の「文字コード」） |
| `Ctrl+Enter` | C/C++: 実装へ飛ぶ（下の「C/C++」）。Markdown: リンク先を開く（`[..](..)`・`[[..]]`・`#見出し`。vault の内外で同じ動き。無ければ作らず知らせる。画像や PDF は既定アプリ） |
| `:CompileCommands` | `compile_commands.json` を作る（下の「C/C++」） |
| `<leader>mb` / `<leader>me` | lazymsbuild（MSBuild の TUI）を開く・隠す / 最後のビルドのエラーを quickfix へ |
| `<leader>mi` | clangd が今のファイルをどの構成（`Debug\|x64` など）で解析しているか（下の「C/C++」） |
| `:ImeState` | IME の状態を出す（0=OFF・1=ON） |

`<leader>fo`・`fw`・`fy` は snacks explorer の中でも、カーソル下のファイルに効く。

起動画面には上から Obsidian Vault（`~/.dotfiles.json` の `vault` と、Obsidian に登録されている vault）・Projects・Recent Files・Keymaps を出す。

### Obsidian

`~/.dotfiles.json` の `vault` を設定した PC で、vault 内の md を開いた時だけ効く。

| キー / コマンド | 動作 |
|---|---|
| `:Obsidian open`・`<leader>fo` | 今のノートを Obsidian アプリで開く |
| `:Obsidian today` | 日次ノート（`exocortex/daily/YYYY-MM-DD.md`）を開く |
| `<CR>` | カーソル下のリンクを開く / チェックボックスを切り替える |
| `[o` / `]o` | 前 / 次のリンクへ移動 |

vault の中に居る時は Obsidian の紫（`#a882ff`）で示す。md 以外のファイルでも効く。

| 場所 | いつ紫になる |
|---|---|
| WezTerm のタブ | Neovim で vault 内のファイルを開いている時・シェルの現在地が vault の中の時（裏のタブは文字だけ紫） |
| Neovim の各ペイン上端のファイル名 | そのペインのファイルが vault の中の時 |

保存時に frontmatter は足さない。新規ノート・テンプレート・画像の置き場は `exocortex/` 配下で、vault のフォルダ構成に合わせて `nvim/lua/plugins/obsidian.lua` に書いてある。

チェックボックスの状態（`note/` の運用・`ai/skills/vault-note/SKILL.md`）は CSS snippet `vault-task-status`（`obsidian/snippets/`）で見分ける。`install.ps1` の 8b が vault に写す（写しは上書きするので、直すのはリポの方）。

| 書き方 | 意味 | 見た目 |
|---|---|---|
| `- [ ]` | 未着手 | Obsidian のまま |
| `- [a]` | AI が実施し、まだ確認していない（まとめへのリンクが同じ行にある） | 紫の箱にきらめき。打ち消し線なし |
| `- [d]` | 確認して完了・後で見返す | 緑の箱にしおり。文字は薄く、打ち消し線なし |
| `- [x]` | 確認して完了・見返さない | Obsidian のまま（チェックと打ち消し線） |

- Tasks プラグインで `[a]` を未完了（一覧に残る）、`[d]` を完了として扱うには、その設定の Task Statuses に `a`（型 ON_HOLD など DONE 以外）と `d`（型 DONE）を足す（vault ごと・手で）
- Obsidian が閉じている時に `install.ps1` を流すと、写すだけで有効にはしない（設定 → 外観 → CSS スニペットで入れるか、開いている時にもう一度流す）

Obsidian の Vim モードで IME を切るには、PC ごとに次を行う。

1. コミュニティプラグイン **Vim IM Select**（`alonelur/vim-im-select-obsidian`）を入れて有効化する
2. その設定の Windows 用 3 項目を埋めて Obsidian を再起動する
   - Windows Default IM: `0`
   - Obtaining Command for Windows: `<clone 先>\tools\bin\ime.exe`
   - Switching Command for Windows: `<clone 先>\tools\bin\ime.exe {im}`

絶対パスしか受けないので、clone 先を移したらここも直す。実際のパスは `install.ps1` が最後に表示する。

### 日本語入力（IME）

Google 日本語入力。ON/OFF はトグルではなく **F13 = OFF・F14 = ON**（キーボード側のレイヤから送る）。

- Neovim は INSERT 以外で必ず IME を切る（`nvim/lua/config/ime.lua`・Windows の Neovim だけ）。INSERT に戻っても ON には戻さないので、日本語を打つ時は F14 を押す
- 設定を変えたら `google-ime\Export-GoogleIme.ps1` でリポへ書き出す。既定と違う所は `google-ime/settings.md`
- ユーザー辞書と学習履歴はリポに入れない

### キーボード（Keychron B1 Pro ANSI）

US 配列のキーボードを日本語版 Windows で使う。設定は 2 層ある。

| 層 | 何が決まる | 持ち運び |
|---|---|---|
| キーボードの中 | キーマップ（Caps=Ctrl・F13/F14 ほか）。編集は [Keychron Launcher](https://launcher.keychron.com/) | キーボードに付いてくる |
| Windows の中 | 物理配列の解釈（US 101 か JIS 106 か） | PC ごとに `Set-UsPhysicalLayout.ps1`（上の「セットアップ」） |

Windows 側をやらないと記号の位置がずれる。キーマップのバックアップは `keychron/keymap/B1-Pro-ANSI.json`（Launcher で書き出した後に `keychron\Export-KeychronKeymap.ps1`）。詳細は `keychron/settings.md`。

### 文字コード（Shift_JIS が混ざったプロジェクト）

CP932 と UTF-8 が混ざったツリーを、そのまま読み書きする。

| 困る場面 | 手段 |
|---|---|
| 開くと化ける | 自動で判定する（`ucs-bom` → `utf-8` → `cp932`）。外した時だけ `:EncOpen cp932` |
| 今どれで開いているか分からない | ステータスライン右に出る（`cp932`・`BOM`・`CR`）。UTF-8 で BOM なしなら何も出ない |
| 日本語で grep が当たらない | `<leader>sJ`。既定の `<leader>sg` は UTF-8 のファイルにしか当たらない |
| lazygit の差分が化ける | `install.ps1` が直す（行ごとに判定するので混在してもよい）。行ステージの画面は化けたまま＝ステージする内容を変えないため（CP932 のまま index に入る） |
| 保存で文字コードを変えたい | 既定は読んだ文字コードのまま書き戻す。変える時だけ `:EncToUtf8` / `:EncToSjis` |
| `:make` や quickfix の出力が化ける | その場で `:set makeencoding=char` |
| プロジェクト全体の内訳を知りたい | `pwsh -File tools\Survey-Encoding.ps1 -Path <フォルダ>`（読み取り専用） |

- `<leader>sJ` は正規表現の意味が少し変わる（`.` が 1 バイト・`\w` と大文字小文字の無視が ASCII だけ）
- 置換（`<leader>sr`）は CP932 のファイルに日本語で当たらない。そのファイルを開いて `:%s` でやる
- Neovim の git ピッカー（`<leader>gd` など）のプレビューと、シェルの `git diff` は化ける

### C/C++（Visual Studio のソリューション）

LazyVim の `lang.clangd` extra を使う。clangd は MSVC と Windows SDK を自分で見つける。ソリューションの読ませ方は [lazymsbuild](https://github.com/6r1ntry52o/lazymsbuild)（`install.ps1` が入れる。設定は `nvim/lua/plugins/lazymsbuild.lua`＝lazymsbuild の `docs/editors/lazyvim.md` と同じ中身）。

| 困る場面 | 手段 |
|---|---|
| 実装に飛びたい | `Ctrl+Enter`。override があればそこへ（複数なら一覧）、無ければ定義へ。型名の上では型の定義へ |
| 定義に飛びたい | `gd`（宣言 `gD`・参照 `gr`・実装 `gI`・型定義 `gy`）。`gI` は仮想関数と派生クラスにしか効かない（clangd の仕様） |
| 実装に飛ばず、ヘッダの宣言で止まる | ① `compile_commands.json` が無いか、インデックスの作成中 ② CP932 のソースで、行末がダメ文字（`表` `ソ` など 2 バイト目が `\`）のコメントの次の行は clangd に見えない（下の注） |
| ソースとヘッダを行き来したい | `<leader>ch` |
| 別の `.cpp` の定義が参照に出ない・プロジェクト固有の `/I` `/D` が効かない | リポで一度 `lazymsbuild init`、その後 `:CompileCommands` |
| ビルドしたい・エラーを見たい | `<leader>mb`（lazymsbuild の TUI。隠してもビルドは続き、終わると通知が出る）・`<leader>me`（エラーを quickfix へ） |
| `<leader>mb` で `lazymsbuild is not on PATH` と出る | 未導入か、入れる前から開いていた Neovim。`pwsh -File tools\Install-Lazymsbuild.ps1` の後、新しいタブで開き直す（案内の文は `config/options.lua` の `vim.g.lazymsbuild_install_hint`） |
| DB が最新か確かめたい | `lazymsbuild check`（全体の点検は `lazymsbuild doctor`） |
| clangd がどの構成で解析しているか知りたい | ステータスライン右の `clangd: Debug\|x64`・`<leader>mi`（下の「どの構成で解析しているか」） |
| LSP が動いているか確かめたい | `<leader>cl` |

`:CompileCommands` は `lazymsbuild sync`。ビルドせずに、リポのルートの `compile_commands.json` を作り直す。以後は lazymsbuild でビルドするたびに DB が追従する。

- ②は clangd がソースを UTF-8 として読むため。`// 表` の `\` が行継続になり、次の行の定義がコメントに飲まれる。コメントの末尾に文字を足せば直る
- 前の `:CompileCommands` が作った `<.sln のある所>\build\compile_commands.json` が残っていると、C/C++ を開いた時に消すか聞かれる（DB が 2 つあると clangd が古い方を読むことがある）
- lazymsbuild が PATH に無い PC では、`:CompileCommands` は前のまま（抽出ツールを直接呼んで `<ルート>\build\compile_commands.json` を作る。抽出ツールの導入は `pwsh -File tools\Install-MsbuildExtractor.ps1`）
- lazymsbuild を上げる時は `install.ps1` を流す（最新のリリースが入る。裏で自動更新はしない）。特定の版にする時は `pwsh -File tools\Install-Lazymsbuild.ps1 -Version <タグ> -Sha256 <SHA256SUMS の SHA256>`。次に `install.ps1` を流すと最新に戻る

#### どの構成で解析しているか

clangd は `compile_commands.json` が変わっても、開いているファイルを自分からは解析し直さない（次の編集か保存で読み直す）。構成を切り替えた直後は、DB と clangd の解析が食い違うことがある。それをステータスラインに出す（`nvim/lua/config/clangd_profile.lua`）。

| 表示 | 意味 |
|---|---|
| `clangd: Debug\|x64`（目立たない色） | clangd が今のファイルを Debug\|x64 の引数で解析した。公開中の DB と同じ |
| `clangd: Debug\|x64 (DB: Release\|x64)`（警告の色） | DB は Release\|x64 なのに、clangd は前の Debug\|x64 のまま。保存（`:w`）すると開いているファイルを全部読み直す（DB の更新から 5 秒ほど後）。直らなければ `:LspRestart clangd` |
| `DB: Debug\|x64` | clangd がこのファイルをまだ解析していない（公開中の DB の構成だけ出す） |
| `clangd: 別の DB`・`clangd: ?`・`clangd: DB の外` | lazymsbuild のどの構成とも合わない引数で解析している（古い `build\compile_commands.json` や `.clangd` の `CompileFlags` を疑う） |

- `<leader>mi` は同じことを、決め手の引数（`/MDd` `_DEBUG` など）と一緒に出す。ヘッダは、どの `.cpp` のコマンドを借りているかも出る
- 目で確かめるなら、`#ifdef _DEBUG` の中は Release で解析されている時にコメントの色になる（clangd が無効な区間をコメントとして送る）
- 仕組み: 公開中の DB は lazymsbuild に聞く（`lazymsbuild check`）。clangd の側は、clangd がファイルを解析するたびに出すログの実際の引数を、lazymsbuild が構成ごとに持つ DB の同じファイルの項目と突き合わせる。エディタの層の機能なので、lazymsbuild 本体ではなくここに置いている

### AI エージェント（Claude Code・GitHub Copilot CLI）

エディタと同じ道具（clangd・lazymsbuild）をエージェントにも使わせ、どのリポで起動しても vault の `note/`（自分の要求の正本）を読んで作業させる。`install.ps1` の 9（`tools/Install-AiAgents.ps1`）が、入っているエージェントの分だけ設定する。

| 何 | Claude Code | GitHub Copilot CLI |
|---|---|---|
| スキル（`ai/skills/`。常に読まれるのは説明の 1 行だけで、本文はその作業の時に読まれる）: `msbuild-cpp`（C/C++）・`vault-note`（note/ の運用・リンクの引き方） | `~/.claude/skills/` に junction | `~/.copilot/skills/` に junction |
| vault を読む（`~/.dotfiles.json` の `vault`） | `~/.claude/settings.json` の `permissions.additionalDirectories` に足す（読むのは許可なし・書くのは権限モードのまま） | 全リポに効く設定が無いので、`powershell/profile.ps1` の `copilot` 関数が起動のたびに `--add-dir` で `note/` と `vault_ai_dir` を渡す（`copilot help` などのサブコマンドはそのまま） |
| `@` で note/ のノートを指す | `@Brain_IF` のように名前で候補に出る（`fileSuggestion` に `tools/bin/file-suggest.exe`。組み込みの候補は起動した場所の中しか出さず、vault を足しても出ない） | パスで打つ（`@~/core/note/Bra` → Tab）。名前だけでは出ない |
| note/ を守るフック（`ai/hooks/note-guard.ps1`） | `~/.claude/settings.json` の `hooks.PreToolUse`（シェルは `note` を含むコマンドの時だけ呼ぶ） | `~/.copilot/hooks/note-guard.json` |
| 言語サーバ | 公式プラグイン `clangd-lsp`（rustup がある PC は `rust-analyzer-lsp` も） | `~/.copilot/lsp-config.json` に clangd（rust-analyzer が動く PC はそれも）。既存の項目は変えず、足す前に `.bak-日時` に退避する |
| clangd の実体 | Neovim の Mason のもの（nvim と同じ版で、索引 `.cache/clangd` も共有）。`powershell/profile.ps1` が PATH の先頭に足す | 同じ |

- エージェントはリポのルートで起動する（nvim の `<leader>ft`）。cwd で開くとリポの一部しか作業範囲にならない
- 効いているかの確認: Claude Code は C/C++ を編集した直後に `Found N new diagnostic issues` と出る（出なければ `/plugin` の Errors）。Copilot CLI は `/lsp`・`/lsp test clangd`、スキルは `copilot skill list`
- clangd が見つからない時は、nvim を一度起動して（Mason が入れる）新しいタブを開く
- この段は取得する（プラグイン・rust-analyzer）だけで、PC の情報を外へ送る仕組みは足さない
- Claude Code は CP932 のファイルを書き換えない（Edit が拒否する）。スキルは「変換しない・聞く」と指示している
- `profile.ps1` は `$env:DOTFILES`（この clone の場所）も設定する。スキルが `tools\Survey-Encoding.ps1` を指すのに使う

#### vault と note/

- `note/` は自分だけが書く場所。エージェントが変えてよいのは、自分の `- [ ]` の行に `[[リンク]]` を挿すことと、実施した行を `- [a]` にして同じ行にまとめへの `[[リンク]]` を足すことだけ（スキル `vault-note` に書き、フックが機械で止める）。それ以外の書き込み（新しいファイル・書き換え・行の追加や削除・`[d]` `[x]`・シェルでの削除や移動）は、その都度こちらに聞いてくる
- まとめと AI の TODO は `vault_ai_dir`（上の「PC ごとの設定」）に分野ごとに書く。未設定ならエージェントは書く前に置き場を聞く
- リンクは `ai/skills/vault-note/scripts/vault-links.ps1 <ノート>` で引く。開いている Obsidian の CLI（1.12 以降・設定 → 一般 → コマンドラインインターフェース）に聞き、そのノートのリンク先・被リンクと、その前後の行だけを JSON で返す（Obsidian が閉じていれば起動する）。`[[名前]]` を grep するより短く、別名・見出し・別フォルダも Obsidian と同じに解く
- フックは `powershell.exe`（5.1）で動く。1 回 0.25 秒ほど。自分自身が壊れた時は止めずに通す
- `file-suggest.exe`（`tools/file-suggest/FileSuggest.cs` を `install.ps1` の 9 が csc でビルド）は Claude Code の `@` の候補を丸ごと受け持つ。プロジェクトのファイルとフォルダ（`rg --files`＝`.gitignore` で外すものは出さない。無ければ `git ls-files`）に、`note/` のノートを絶対パスで足す。`note/` かノートの絶対パス（`~/…` も）で打ち始めるとノートだけになる。1 回 0.05 秒ほど（ホームのような巨大なフォルダで起動した時だけ 1.7 秒）。自分で `fileSuggestion` を設定していれば触らない
- Copilot CLI のフックが受け取る引数の名前は公式に書かれていない。両方の名前（`file_path`・`path` など）を読み、読めない形は聞く側に倒す。実際に届く形を見るには、`NOTE_GUARD_LOG` にファイルを指定して起動する
- 効いているかの確認: vault の外のリポでエージェントを起動し、「vault の note/ に test.md を作って」と頼む → 許可を求められれば効いている（断る）

## 構成

設定の実体はすべてリポにあり、PC 側は読み込む 1 行やリンクを持つだけ。

```
PC 側（install.ps1 が作る）               リポ側（実体）
~/.wezterm.lua（スタブ）       ──読む──▶ wezterm/
$PROFILE（1 行を追記）         ──読む──▶ powershell/profile.ps1
WSL の ~/.bashrc・~/.zshrc     ──読む──▶ wsl/osc7.sh・osc7.zsh ─▶ wsl/aliases.sh
%LOCALAPPDATA%\nvim            ─junction▶ nvim/
~/.claude/skills/msbuild-cpp   ─junction▶ ai/skills/msbuild-cpp/（Claude Code）
~/.copilot/skills/msbuild-cpp  ─junction▶ ai/skills/msbuild-cpp/（Copilot CLI）
~/.copilot/lsp-config.json     リポの外（足りない言語サーバの項目だけ install.ps1 が足す）
~/.claude/settings.json        リポの外（vault の additionalDirectories・note-guard のフック・fileSuggestion だけ install.ps1 が足す）
                               ─呼ぶ▶ ai/hooks/note-guard.ps1・tools/bin/file-suggest.exe
~/.copilot/hooks/note-guard.json  install.ps1 が書く ─呼ぶ▶ ai/hooks/note-guard.ps1
<vault>/.obsidian/snippets/vault-task-status.css  写し（install.ps1 が上書き）◀─ obsidian/snippets/
~/.dotfiles.json               ◀─読まれる─ wezterm・nvim・profile.ps1
%LOCALAPPDATA%\nvim-data       リポの外（install.ps1 は消さない。lazy\・mason\ は消しても入り直す。shada\＝Recent Files と Projects の元・sessions\・undo\ は消すと戻らない）
```

```
dotfiles-windows/
├── install.ps1              セットアップ
├── dotfiles.example.json    ~/.dotfiles.json の雛形
├── wezterm/                 wezterm.lua（本体）・keybinds.lua（キー）・machine.lua（~/.dotfiles.json を読む）
├── powershell/profile.ps1   現在地の通知・vi 系のエイリアス・vault・Mason の bin を PATH へ（AI エージェント用）・copilot に note/ を渡す
├── ai/skills/               AI エージェントのスキル（Claude Code と Copilot CLI が同じものを読む）・vault-note/scripts/vault-links.ps1
├── ai/hooks/                note-guard.ps1（note/ を守る PreToolUse フック・両エージェント共通）
├── obsidian/snippets/       vault に写す CSS（tools/Install-ObsidianSnippets.ps1 が写す）
├── tools/file-suggest/      FileSuggest.cs（→ bin/file-suggest.exe・Claude Code の @ の候補に note/ を足す）
├── wsl/                     install.sh・osc7.sh / osc7.zsh（現在地の通知）・aliases.sh
├── nvim/                    LazyVim/starter が元
│   ├── lua/config/          options・keymaps・autocmds の上書きと、
│   │                        encoding・ime・winpath・vault（紫の表示）・machine（~/.dotfiles.json を読む）・jump（Ctrl+Enter）・wezterm・
│   │                        clangd_profile（clangd がどの構成で解析しているか）
│   ├── lua/plugins/         encoding・obsidian・snacks・clangd・lazymsbuild・colorscheme
│   ├── lazy-lock.json       プラグインの版の固定
│   └── lazyvim.json         入れた extras
├── tools/                   Survey-Encoding.ps1・Install-Lazymsbuild.ps1・Install-MsbuildExtractor.ps1・Install-AiAgents.ps1・
│                            ime/Ime.cs・cp932/Cp932ToUtf8.cs（→ bin/*.exe・git 管理外）
├── google-ime/              Google 日本語入力の設定と Export / Restore
└── keychron/                キーマップのバックアップと Windows 側の設定スクリプト
```

## 設定を変える・同期する

- リポの中のファイルを編集する。WezTerm は保存で自動的に読み直す
- 他の PC へは `git push` → 向こうで `git pull`
- Neovim のプラグインを更新（`:Lazy update`）したら `nvim/lazy-lock.json` も commit する。他の PC では `git pull` のあと `:Lazy restore`
- `:LazyExtras` で足した機能は `nvim/lazyvim.json` に入るので、これも commit する

## 外す

- `~/.wezterm.lua` を消す（`.bak-*` があれば戻す）
- `$PROFILE` と WSL の `~/.bashrc`・`~/.zshrc` から、末尾が `# managed by dotfiles-windows/install.ps1` の行を消す
- `cmd /c rmdir %LOCALAPPDATA%\nvim` で junction を外す（`nvim.bak-*` があれば戻す）。プラグインも消すなら `%LOCALAPPDATA%\nvim-data` の `lazy` と `mason` を消す（`nvim-data` ごと消すと Recent Files・Projects・セッション・undo の履歴も消える）
- Google 日本語入力は `config1.db.bak-*` を元の名前に戻す
- Obsidian の Vim IM Select を無効化する
- lazymsbuild は `%LOCALAPPDATA%\Programs\lazymsbuild` を消し、ユーザーの PATH からその行を外す（状態は `%LOCALAPPDATA%\lazymsbuild`、抽出ツールは `%LOCALAPPDATA%\msbuild-extractor`）
- vault 関係は `~/.claude/settings.json` の `hooks.PreToolUse` から `note-guard.ps1` を呼ぶ 3 項目・`fileSuggestion`・`permissions.additionalDirectories` の vault を消し（`.bak-*` があれば戻す）、`~/.copilot/hooks/note-guard.json` を消す。CSS は Obsidian の設定で切って `<vault>/.obsidian/snippets/vault-task-status.css` を消す
- AI エージェントは `cmd /c rmdir %USERPROFILE%\.claude\skills\msbuild-cpp` と `cmd /c rmdir %USERPROFILE%\.copilot\skills\msbuild-cpp`（`vault-note` も同じ・junction だけ外れる）、`~/.copilot/lsp-config.json` から `clangd`・`rust-analyzer` の項目を消す（`.bak-*` があれば戻す）、`claude plugin uninstall clangd-lsp@claude-plugins-official`（`rust-analyzer-lsp` も）、`rustup component remove rust-analyzer`
- `~/.dotfiles.json` を消す
