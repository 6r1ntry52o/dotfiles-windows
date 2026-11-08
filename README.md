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
| 7 | `tools/bin/ime.exe` をビルドする（Obsidian 用。8c がプラグインの隣に写す） |
| 7b | `tools/bin/cp932-to-utf8.exe` をビルドし、`%LOCALAPPDATA%\lazygit\config.yml` に差分の表示フィルタとして書く（下の「文字コード」。自分で書いた `config.yml` があれば触らず、足す内容を警告で出す。clone 先を移したら流し直す） |
| 7c | `tools/bin/utf8-mirror.exe` をビルドする（CP932 のソースを clangd に UTF-8 で見せる＝下の「CP932 のソースと clangd」。有効にするのは Neovim） |
| 8 | `~/.dotfiles.json` を、無ければ作る（下の「PC ごとの設定」） |
| 8b | `obsidian/snippets/*.css`（note/ のチェックボックスの状態の見た目）を vault の `.obsidian/snippets` に写し、Obsidian が開いていれば有効にする（下の「Obsidian」） |
| 8c | Obsidian のキーを LazyVim に揃える（Vim モード・`Ctrl+h/j/k/l` で分割・`Shift+h/l` でタブ・`Ctrl+o/i` で戻る・進む・モードの表示・今の行の色・相対の行番号・ヤンクした所を光らせる・INSERT 以外で IME を OFF）。ホットキーを vault に混ぜ、vimrc を写し、Vim モードを on にし、Obsidian が開いていればプラグイン Vimrc Support を入れ、このリポのプラグイン dotfiles-vim を `ime.exe` と一緒に写して有効にする（下の「Obsidian」。Vimrc Support の取得は `-SkipPackages` で飛ばせる） |
| 9 | AI エージェント（Claude Code・GitHub Copilot CLI）が入っている PC で、スキルを見せ、エディタと同じ言語サーバを使えるようにする。vault がある PC では、どのリポから起動しても vault を読めるようにし、note/ を守るフックをつなぐ（下の「AI エージェント」。プラグインと rust-analyzer の取得は `-SkipPackages` で飛ばせる） |

管理者権限は要らない。次は `install.ps1` がやらないので、要る PC だけ手で行う。

| 何 | 手順 |
|---|---|
| PowerShell 7（MSI 版） | **管理者**で `winget install --id Microsoft.PowerShell -e --source winget --scope machine`。Store 版（MSIX）が入っていたら `Get-AppxPackage Microsoft.PowerShell \| Remove-AppxPackage` で外す。Store 版は WindowsApps のエイリアスで、Neovim から起動できない＝`<leader>ft` が 5.1 に落ちて `claude` などの `.ps1` が実行ポリシーで止まる |
| Google 日本語入力の設定 | `google-ime\Restore-GoogleIme.ps1` を流す（今の設定は `.bak-日時` に退避） |
| US 配列キーボード | **管理者**で `keychron\Set-UsPhysicalLayout.ps1` を流して再起動（`-Show` で確認・`-Revert` で戻す） |

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
| `vault` | Obsidian vault の場所（WezTerm・Neovim・PowerShell・AI エージェントが読む） | Obsidian 関連の機能を読み込まない（WezTerm は起動時のタブが 1 つ） |
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

起動するとタブが 2 つ開き、2 つ目が前に出る。

| タブ | 中身 |
|---|---|
| 1 | vault（`~/.dotfiles.json` の `vault`）を現在地にした Neovim（LazyVim の起動画面）。PowerShell 越しに開くので、Neovim を閉じても vault に居るシェルとして残る |
| 2 | PowerShell（ホーム） |

- `vault` が未設定・見つからない PC では、今までどおり PowerShell のタブ 1 つ
- 起動時の最初のウィンドウだけ。開いている WezTerm からもう一度起動した時・`wezterm start --cwd …` などで場所やコマンドを渡した時は、そのタブ 1 つ

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
| `Ctrl+Enter` | C/C++: 実装へ飛ぶ（下の「C/C++」）。Markdown: リンク先を開く（`[..](..)`・`[[..]]`・`#見出し`。vault の内外で同じ動き。無ければ作るか `y`/`n` で聞く＝下の「Obsidian」。画像や PDF は既定アプリ） |
| `gaI` / `gaO` | 呼び出し元 / 呼び出し先をツリーで出す（下の窓。`l` 開く・`h` 閉じる・`L` 下を全部開く・`<CR>` 呼んでいる場所へ・`p` 窓に残ったまま見る・`q` 閉じる。`↻` は再帰）。一段だけの一覧は LazyVim の `gai` / `gao` |
| `:CompileCommands` | `compile_commands.json` を作る（下の「C/C++」） |
| `<leader>mb` / `<leader>me` | lazymsbuild（MSBuild の TUI）を開く・隠す / 最後のビルドのエラーを quickfix へ |
| `<leader>mi` | clangd が今のファイルをどの構成（`Debug\|x64` など）で解析しているか（下の「C/C++」） |
| `:ImeState` | IME の状態を出す（0=OFF・1=ON） |

`<leader>fo`・`fw`・`fy` は snacks explorer の中でも、カーソル下のファイルに効く。

起動画面には上から Obsidian Vault（`~/.dotfiles.json` の `vault` と、Obsidian に登録されている vault）・Projects・Recent Files・Keymaps を出す。

パスが長いファイル（およそ 250 文字以上。Windows の長いパスの設定が無効な PC では、およそ 210 文字以上）は、スワップファイルと undo ファイルを作らない。名前が Windows の上限を越えて作れず、開くたびに `E303`、保存のたびに `E828` が出ていたため（`nvim/lua/config/longpath.lua`）。そのファイルは、落ちた時に戻せず、閉じた後の undo も残らない。

259 文字以上のフォルダは、Windows がプログラムの作業フォルダにできない（LongPathsEnabled が有効でも）。そこにあるファイルを開くと gitsigns が git を起動できずにエラー（`ENOENT`）を出していたので、そういうファイルだけリポの場所を先に渡している（`nvim/lua/plugins/gitsigns.lua`）。git 自身の `Filename too long` は `install.ps1` が `core.longpaths` を入れて直す。残る限界: そこで `Snacks.lazygit.log_file`（今のファイルの履歴）は開けない。

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

`Ctrl+Enter` で先の無いリンクを踏むと、作るかを `y`/`n` で聞く（作る場所も出る）。`y` で空のノートを作って開く。場所は Obsidian でそのリンクを踏んだ時と同じで、その PC の vault の設定を読む（`nvim/lua/config/newnote.lua`）。

| リンク | 作る場所 |
|---|---|
| `[[名前]]`（フォルダなし） | dated-folders プラグインが有効なら、その日付のフォルダ（`<Base folder>/YYYY/MM-DD(Wnn)` など。無ければ作る・`Notes created from links` の設定にも従う）。無効なら Obsidian の「新規ノートの既定の場所」（`.obsidian/app.json` の `newFileLocation`） |
| `[[a/名前]]`（フォルダあり） | 書いたとおり（vault から。`./` `../` で始まれば今のノートから） |
| vault の外のリンク | 今のファイルのフォルダから |

作るのは md のノートだけ（画像などのリンクは知らせるだけ）。

チェックボックスの状態（`note/` の運用・`ai/skills/vault-note/SKILL.md`）は CSS snippet `vault-task-status`（`obsidian/snippets/`）で見分ける。`install.ps1` の 8b が vault に写す（写しは上書きするので、直すのはリポの方）。

| 書き方 | 意味 | 見た目 |
|---|---|---|
| `- [ ]` | 未着手 | Obsidian のまま |
| `- [a]` | AI が実施し、まだ確認していない（まとめへのリンクが同じ行にある） | 紫の箱にきらめき。打ち消し線なし |
| `- [d]` | 確認して完了・後で見返す | 緑の箱にしおり。文字は薄く、打ち消し線なし |
| `- [x]` | 確認して完了・見返さない | Obsidian のまま（チェックと打ち消し線） |

- Tasks プラグインで `[a]` を未完了（一覧に残る）、`[d]` を完了として扱うには、その設定の Task Statuses に `a`（型 ON_HOLD など DONE 以外）と `d`（型 DONE）を足す（vault ごと・手で）
- Obsidian が閉じている時に `install.ps1` を流すと、写すだけで有効にはしない（設定 → 外観 → CSS スニペットで入れるか、開いている時にもう一度流す）

Obsidian のキーは LazyVim に揃える（`install.ps1` の 8c・`tools/Install-ObsidianKeys.ps1`）。

| キー | 動作 | 正本 |
|---|---|---|
| `Ctrl+h` / `Ctrl+j` / `Ctrl+k` / `Ctrl+l` | 左・下・上・右の分割（タブグループ）へ移る。どのモードでも、閲覧表示でも効く | `obsidian/hotkeys.json` |
| `Shift+h` / `Shift+l`（ノーマルモード） | 同じタブグループの前・次のタブへ | `obsidian/vimrc` |
| `Space` で始まるキー（ノーマルモード） | LazyVim の `<leader>`（下の表） | `obsidian/vimrc` |
| `h` / `j` / `k` / `l`（ファイルエクスプローラ） | LazyVim の explorer と同じ。`j`/`k` で上下、`h` で閉じる（ファイルや閉じたフォルダでは親を閉じてそこへ）、`l` でフォルダの開閉・ファイルを開く。`Space e` で入るとすぐ使える | `obsidian/plugins/dotfiles-vim` |
| `Ctrl+↑` / `Ctrl+↓` / `Ctrl+←` / `Ctrl+→` | 今の分割の高さを増やす・減らす、幅を減らす・増やす（LazyVim の `<C-Up>` など。40px ずつ）。サイドバーの中では幅はサイドバーの幅、分割が 1 列だけの時は開いているサイドバーを隣として動かす。INSERT と入力欄では元の動き（単語の移動など） | `obsidian/plugins/dotfiles-vim` |
| （今いるタブグループの今のタブ） | アクセントの色にする（LazyVim の bufferline の今のバッファと同じ） | `obsidian/plugins/dotfiles-vim/styles.css` |
| `Ctrl+Shift+H` / `Ctrl+Shift+K` / `Ctrl+Shift+L` | 置換・リンクの挿入・チェックボックスの切り替え（Obsidian 既定の `Ctrl+H/K/L` から移した） | `obsidian/hotkeys.json` |
| `Ctrl+o` / `Ctrl+i`（ノーマルモード） | 前・次に開いていた所へ戻る・進む（Obsidian のタブの履歴）。ノーマルモードの編集画面の外では、元のクイックスイッチャー・斜体 | `obsidian/hotkeys.json`・`obsidian/plugins/dotfiles-vim` |
| （ステータスバーの左端） | 今のモードと、押しかけのキー（下） | `obsidian/plugins/dotfiles-vim` |
| （今いる分割の編集画面） | カーソルの行を今のモードの色で塗る（下） | `obsidian/plugins/dotfiles-vim/styles.css` |
| （行番号） | 今の行からの距離で出す。今の行だけ本来の番号（下） | `obsidian/plugins/dotfiles-vim` |
| （ヤンク） | ヤンクした所を一瞬光らせる（下） | `obsidian/plugins/dotfiles-vim` |
| （INSERT 以外） | IME を OFF にする（下） | `obsidian/plugins/dotfiles-vim` |

8c がすること（何度流してもよい）:

- `obsidian/hotkeys.json` を vault の `.obsidian/hotkeys.json` に混ぜる。Obsidian で別のキーを付けたコマンドは触らずに警告する（リポのものにするには、設定 → ホットキーでそのコマンドを既定に戻して流し直す）。同じキーが別のコマンドにも付いていても警告する
- `obsidian/vimrc` を vault 直下の `.obsidian.vimrc` に写す（写しは上書きするので、直すのはリポの方）
- `.obsidian/app.json` の `vimMode` を `true` にする（Vim モード）
- コミュニティプラグイン **Vimrc Support**（`obsidian-vimrc-support`）を Obsidian の CLI で入れて有効にする。その vault が Obsidian で開いている時だけ行う（閉じていると CLI が Obsidian を起動してしまうため）
- このリポのプラグイン **Vim like Neovim (dotfiles)**（`obsidian/plugins/dotfiles-vim`。モードの表示・今の行の色・相対の行番号・ヤンクの光・IME・`Ctrl+o/i`・エクスプローラの hjkl・`Ctrl+矢印`・今のタブの色）を、それが呼ぶ `tools/bin/ime.exe`（7 で作る）と一緒に `<vault>/.obsidian/plugins/dotfiles-vim/` へ写して有効にする（写しは上書きするので、直すのはリポの方）。開いている Obsidian には CLI の `eval` で読み込ませる（再起動は要らない）。閉じていれば有効なプラグインの一覧に足し、次に開いた時に読まれる

いつ効くか:

- キーと Vim モードは、開いている Obsidian にもすぐ効く。読み込みの操作は要らない（`hotkeys.json` の書き換えは Obsidian が読み直す。`app.json` は読み直さないことがあるので、8c が CLI の `eval` で同じ設定を入れる）
- `Shift+h/l` は、Vimrc Support が入った後にタブを 1 回切り替えると効く。Vimrc Support は vimrc をウィンドウごとに 1 回だけ読むので、`obsidian/vimrc` を変えた時は Obsidian を開き直す
- Vimrc Support を CLI で入れるには、Obsidian のインストーラが 1.11.7 以降であること（`obsidian version` の `installer`）。古いインストーラの CLI は、`:` を含む引数の後ろに別の引数があるとすぐ終わる（1.9.14 で実測）ので `plugin:install id=…` が通らない。その時 8c は手順を出すだけなので、設定 → コミュニティプラグインで入れて有効にするか、[obsidian.md](https://obsidian.md/download) からインストーラを入れ直して流し直す
- Obsidian が閉じている時に流すと、キーと Vim モードは次に開いた時に効く。プラグインは、開いている時にもう一度流すと入る（設定 → コミュニティプラグインから入れてもよい）
- Obsidian Sync でメイン設定とホットキーを同期していれば、キーと Vim モードは他の PC にも届く。スマホは Vim モードを端末ごとに持つので、ここで on にしても変わらない

`Space` は LazyVim と同じくリーダーにする。効くのは、編集画面のノーマルモード・ファイルエクスプローラ・閲覧表示・新しいタブの画面（閲覧表示の Space のスクロールと、エクスプローラの Space の「開く」はやめた。開くのは `l` と Enter）。他のサイドバー（アウトライン・検索など）・Canvas・グラフ・INSERT では効かない。エクスプローラから押すと、最後に開いていたノートのタブで動く（分割・タブを閉じる・アウトラインがノートに効く）。

| キー | LazyVim | Obsidian |
|---|---|---|
| `Space Space` | Find Files | クイックスイッチャー（何も打たなければ最近開いたファイル＝`<leader>fr` も兼ねる） |
| `Space /` | Grep | すべてのファイルを検索（左のサイドバーの検索ペイン） |
| `Space e` | Explorer | ファイルエクスプローラで今のノートを選ぶ |
| `Space s C`・`Space :` | Commands・Command History | コマンドパレット（履歴は無い） |
| `Space s s` | LSP Symbols | 今のノートのアウトライン（見出し） |
| `Space b d` | Delete Buffer | 今のタブを閉じる |
| `Space -`・`Space \|` | 下・右に分割 | 下・右に分割 |
| `Space \`・`Space ]` | （無い） | 左・右のサイドバーを開く・閉じる（`]` は Vim の「次・先」の括弧なので右） |

- キーを足す時は `obsidian/vimrc` に `exmap <名前> obcommand <コマンド>` と `nmap <Space><キー> :<名前><CR>` を書く。編集画面の中は Vim がそれを読み、編集画面の外は `dotfiles-vim` が同じ行を読む（プラグインは読み込む時に 1 回読むので、変えたら Obsidian を開き直す）
- Obsidian の Vim には `<leader>`（`mapleader`）が無いので、vimrc には `<Space>` と書く。Space には「右へ 1 文字」が付いていて、完全に合うキーは長い候補があっても待たずに動くので、先に `unmap <Space>` で外している
- which-key のような候補の一覧は出ない。Space の後は、次のキーを押すまで待つ（時間切れは無い）。押しかけのキーはモードの右に出る（`<Space>s` など。Neovim の showcmd）

エクスプローラの hjkl と `Ctrl+矢印` は、エクスプローラの木が持つキーの表（Obsidian の矢印・Enter と同じ所）の先頭に足す。名前の変更の入力欄では効かない（文字が打てる）。エクスプローラに入った時も IME を切る（Neovim の explorer もノーマルモードなので）。`Ctrl+矢印` は Obsidian のホットキーにしていない（ホットキーは、コマンドが何もしない時もキーを止めるので、INSERT の単語の移動が効かなくなる）。エクスプローラ以外の木（アウトライン・検索の結果など）の中では、その木の `Ctrl+矢印` のまま。

`Ctrl+o/i` をプラグインのコマンドにしているのは、Obsidian がホットキーを編集画面より先に拾うため（vimrc の `nmap <C-o>` には届かない）。このコマンドは、ノーマルモードの編集画面にフォーカスがある時だけ戻る・進むを呼び、それ以外では元のクイックスイッチャー（`Ctrl+O`）・斜体（`Ctrl+I`）を呼ぶ。自分で付けたキーは既定のキーより先に試されるので、設定 → ホットキーで `Ctrl+O`・`Ctrl+I` が重なって見えても、この順で動く。nvim のジャンプリストと違い、同じノートの中の移動（`G` や検索）は戻らない。

ステータスバーの左端に今のモードを出す（lualine と同じ名前と色。kanagawa wave）。編集画面でない時・閲覧表示では出さない。

| 表示 | いつ |
|---|---|
| NORMAL（青） | ノーマルモード |
| INSERT（緑） | INSERT |
| VISUAL・V-LINE・V-BLOCK（紫） | `v`・`V`・`Ctrl+v` |
| REPLACE（橙） | `R` |
| COMMAND（黄） | `/`・`:` の入力欄が開いている時 |

モードの右には、押しかけのキー（`<Space>s`・`2d` など。Neovim の showcmd）を出す。ノーマルとビジュアルの時だけ。

カーソルの行は、Neovim の cursorline と同じく、今いる分割の編集画面でだけ塗る（帯は常に 1 つ）。帯の色は今のモードの色（上の表と同じ青・緑・紫・橙・黄）を透かしたもの。行番号は太字にし、行番号の桁も同じ地にする。番号の色は Neovim の CursorLineNr に合わせ、暗いテーマは `#ff9e3b`、明るいテーマは `#e98a00`（kanagawa の wave・lotus）。帯は半透明にして重ねるので、選択（ビジュアルモードも）とコードブロックの地は消えない。表のセルを編集している時は、セルのモードの色になる。Neovim の十字の縦（cursorcolumn）は作らない（Obsidian は文字の幅がそろわず、折り返しもあるため）。

行番号は、Neovim（LazyVim の `number` + `relativenumber`）と同じく、今の行からの距離で出す。今の行だけ本来の番号にする（`5j` の 5 がそのまま読める）。行番号の欄は Obsidian のもの（設定 → エディタ → 行番号を表示）をそのまま使い、数字の書き方だけを変えるので、行番号を切っていれば何も出ない。Obsidian の行番号はノートの行で数えるので、折りたたんだ所や、表のように何行もまとめて描くブロックの所では、`j` で動く数と合わないことがある。

ヤンクした所は、Neovim（LazyVim の `vim.hl.on_yank()`）と同じく 150ms だけ光らせる。色も Neovim の `IncSearch`（`nvim/lua/plugins/colorscheme.lua`。roninYellow `#ff9e3b` の地に sumiInk0 の文字）と同じで、明るいテーマでも同じ色。Neovim は太字だが、Obsidian は文字の幅が変わって行の折り返しが動くので太字にしない。光るのは `y` の演算子すべて（`yiw`・`yy`・`Y` など）とビジュアルモードの `y`（`Ctrl+v` のブロックも）。`"_y`（Neovim も同じ）・`d`・`c`・`:yank` では光らない。ライブプレビューで絵に置き換わる所（箇条書きの点・チェックボックスなど）は塗られない。

Obsidian の Vim モードでも、Neovim と同じく INSERT 以外では IME を必ず OFF にする。Esc で戻った直後に IME が ON のままだと、`h/j/k/l` が IME に食われてノーマルモードのキーが通らないため。

| 切る時 | Neovim で同じもの |
|---|---|
| INSERT（置換を含む）を抜けた時 | `InsertLeave` |
| 編集画面にフォーカスが入った時（`/`・`:` の入力欄から戻った時・別のペインやサイドバーから入った時） | `CmdlineLeave` |
| Obsidian に戻ってきた時 | `FocusGained` |
| ノートを開いた時・プラグインを有効にした時 | `VimEnter` |

- INSERT 中の編集画面は触らない。INSERT に入っても ON には戻さないので、日本語を打つ時は F14 を押す
- IME を切るのは `ime.exe`（前面のウィンドウの IME を外から切る）。プラグインから見て隣にあるので、clone 先を移しても設定は要らない
- Obsidian Sync でプラグインを同期していると、プラグインだけ他の PC にも届く。`ime.exe` が無い PC では IME だけ切らない（その PC で `install.ps1` を流すと効く）。スマホでは読み込まれない

### 日本語入力（IME）

Google 日本語入力。ON/OFF はトグルではなく **F13 = OFF・F14 = ON**（キーボード側のレイヤから送る）。

- Neovim と Obsidian の Vim モードは INSERT 以外で必ず IME を切る（`nvim/lua/config/ime.lua`・`obsidian/plugins/dotfiles-vim`・Windows だけ）。INSERT に戻っても ON には戻さないので、日本語を打つ時は F14 を押す
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
| grep で CP932 のファイルが化ける・日本語で当たらない | 自動（既定の grep＝`<leader>/`・`sg`・`sG`・`sw`・`sW`・`sB` が、元のファイルを UTF-8 と CP932 の両方で探し、一覧と右のプレビューを UTF-8 に直して出す）。clangd 用の写しは使わない |
| ピッカーの右のプレビューが化ける（ファイル検索・explorer・LSP の参照・quickfix など） | 自動（CP932 の行を UTF-8 に直して見せる）。git の hunk の一覧（`<leader>gd`）も。`<Tab>` でステージする中身は CP932 のまま |
| CP932 のリポで、ASCII だけのファイルや新しいファイルに日本語を足すと UTF-8 で保存される（MSVC は BOM なしのソースを CP932 で読む＝化ける・次の行が消える） | 自動（写しを使っているリポの C/C++ は CP932 で保存し、通知が出る。CP932 に無い文字があれば UTF-8 の BOM 付き）。UTF-8 にしたい時は `:EncToUtf8` |
| シェルの `git status` で日本語のファイル名が `"\350\241\250.cpp"` になる | `install.ps1` が `core.quotepath=false` を入れる |
| lazygit の差分が化ける | `install.ps1` が直す（行ごとに判定するので混在してもよい）。行ステージの画面は化けたまま＝ステージする内容を変えないため（CP932 のまま index に入る） |
| 保存で文字コードを変えたい | 既定は読んだ文字コードのまま書き戻す。変える時だけ `:EncToUtf8` / `:EncToSjis` |
| clangd が CP932 のヘッダを読み違える（無いはずのエラー・定義に飛べない・列がずれる） | 自動（CP932 の C/C++ を開いたリポで、UTF-8 に直した写しを clangd に見せる）＝下の「CP932 のソースと clangd」 |
| `:make` や quickfix の出力が化ける | その場で `:set makeencoding=char` |
| プロジェクト全体の内訳を知りたい | `pwsh -File tools\Survey-Encoding.ps1 -Path <フォルダ>`（読み取り専用） |

- grep の限界: CP932 のファイルでは、正規表現の `.`・`\w`・`[…]` が日本語の 1 文字に当たらない（バイト単位で照合する）。`\p{…}` を使った検索と、CP932 に無い文字（絵文字など）を含む検索は CP932 のファイルに当たらない。一覧の CP932 の行は一致箇所に色が付かない（プレビューは付く）
- 置換（`<leader>sr`）は CP932 のファイルに日本語で当たらない。そのファイルを開いて `:%s` でやる
- 化けたままのもの: git を走らせるピッカーのプレビュー（`<leader>gs`・`gl`・`gf` などの差分とコミット）・シェルの `git diff`・PowerShell で UTF-8 のコマンドの出力を受けた時（`$x = git log …`・`git log | sls`。コンソールが CP932 のため。画面にそのまま出す分は化けない）

### C/C++（Visual Studio のソリューション）

LazyVim の `lang.clangd` extra を使う。clangd は MSVC と Windows SDK を自分で見つける。ソリューションの読ませ方は [lazymsbuild](https://github.com/6r1ntry52o/lazymsbuild)（`install.ps1` が入れる。設定は `nvim/lua/plugins/lazymsbuild.lua`＝lazymsbuild の `docs/editors/lazyvim.md` と同じ中身）。

| 困る場面 | 手段 |
|---|---|
| 実装に飛びたい | `Ctrl+Enter`。override があればそこへ（複数なら一覧）、無ければ定義へ。型名の上では型の定義へ |
| 定義に飛びたい | `gd`（宣言 `gD`・参照 `gr`・実装 `gI`・型定義 `gy`）。`gI` は仮想関数と派生クラスにしか効かない（clangd の仕様） |
| 実装に飛ばず、ヘッダの宣言で止まる | ① `compile_commands.json` が無いか、中身が空か（プロジェクトの読み込みでビルドが失敗した時も、空の DB が置かれた。`lazymsbuild check` の `coverage` が `0/…`。`Ctrl+Enter` がその時に知らせる）、インデックスの作成中 ② CP932 の `.cpp` で、行末がダメ文字（`表` `能` など 2 バイト目が `\`）のコメントの直後の定義は、そのファイルを開くまで飛べない（下の「CP932 のソースと clangd」） |
| 呼び出し元をたどりたい | `gaI`（ツリー・上の「Neovim」）。`gai` は一段だけの一覧で、1 件なら一覧を出さずにそこへ飛ぶ。別のファイルからの呼び出しはインデックスから引くので、DB が空の時やインデックスの作成中は同じファイルの中しか出ない |
| ソースとヘッダを行き来したい | `<leader>ch` |
| 別の `.cpp` の定義が参照に出ない・プロジェクト固有の `/I` `/D` が効かない | リポで一度 `lazymsbuild init`、その後 `:CompileCommands` |
| ビルドしたい・エラーを見たい | `<leader>mb`（lazymsbuild の TUI。隠してもビルドは続き、終わると通知が出る）・`<leader>me`（エラーを quickfix へ） |
| `<leader>mb` で `lazymsbuild is not on PATH` と出る | 未導入か、入れる前から開いていた Neovim。`pwsh -File tools\Install-Lazymsbuild.ps1` の後、新しいタブで開き直す（案内の文は `config/options.lua` の `vim.g.lazymsbuild_install_hint`） |
| DB が最新か確かめたい | `lazymsbuild check`（全体の点検は `lazymsbuild doctor`） |
| clangd がどの構成で解析しているか知りたい | ステータスライン右の `clangd: Debug\|x64`・`<leader>mi`（下の「どの構成で解析しているか」） |
| LSP が動いているか確かめたい | `<leader>cl` |

`:CompileCommands` は `lazymsbuild sync`。ビルドせずに、リポのルートの `compile_commands.json` を作り直す。以後は lazymsbuild でビルドするたびに DB が追従する。

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

#### CP932 のソースと clangd

clangd はソースを UTF-8 として読む。CP932 のヘッダでは、行末が `表` `能` `ソ` など 2 バイト目が `\` の文字のコメントが行継続になり、次の行（宣言・メンバ・`#endif`）が clangd から消える（無いはずのエラーが出る・定義に飛べない）。日本語より後ろの列もずれ、UTF-16 のヘッダは読めない。MSVC は CP932 として読むので、ビルドは通る。

そこで、UTF-8 に直した写しを、元のパスのまま clangd に見せる（clang の VFS overlay）。ソースは変えず、リポにも何も書かない。

| いつ | 何が起きる |
|---|---|
| CP932 の C/C++ を開いた時・保存した時 | そのリポ（`.git` か `.svn` のある所、無ければ `compile_commands.json` のある所）で有効にし、clangd を再起動する（1 回だけ通知が出る） |
| 有効なリポで C/C++ を開いた時・フォーカスが戻った時・lazygit などのターミナルを閉じた時 | 写しを今のソースに合わせる（裏で。更新日時と大きさが変わったファイルだけ読む） |
| 有効なリポで C/C++ を保存した時 | そのファイルの写しを替えてから、clangd に保存を知らせる（40 ms ほど待つ） |

| コマンド | 動作 |
|---|---|
| `:Utf8Mirror` | 今のリポで使っているか・写しの件数 |
| `:Utf8Mirror on` / `off` | 手で有効にする / 外す（clangd の設定の節と写しを消し、clangd を再起動） |
| `:Utf8Mirror sync` | 写しを今すぐ合わせる（Neovim の外で大きく変えた後） |

- 置き場: 写しと overlay は `%LOCALAPPDATA%\utf8-mirror\<フォルダ名>-<ハッシュ>`（その PC の中だけ）。clangd への指定は `%LOCALAPPDATA%\clangd\config.yaml` のリポごとの節（`# >>> utf8-mirror <リポ>`。他の内容は触らない）。AI エージェントの clangd にも効く
- 長いパス（260 文字以上）も写す。Windows の長いパスの設定（LongPathsEnabled）は要らない。写しは元より長いパスになる（置き場の分）ので、元が 260 文字に収まっていても越えることがある。写せなかったファイルと、一覧を取れなかったフォルダは警告に出る。それらは次の同期でやり直す（index に残さない）ので、直った後に作り直す物は無い。一から作り直したい時は `:Utf8Mirror off` → `on`
- MSVC の `/source-charset:…`・`/execution-charset:…` は、そのリポでは clangd に渡さない（clang は UTF-8 しか受け付けず、全ファイルの 1 行目がエラーになる）
- 限界 1: clangd の裏のインデックスは `.cpp` 本体を写しでなくディスクから読む（写しが効くのは `#include` されるファイル）。行末がダメ文字のコメントの直後にある `.cpp` の定義は、別のファイルからはヘッダの宣言に飛ぶ。その `.cpp` を一度開くと飛べる（開いたファイルはエディタが渡す UTF-8 で解析する。閉じた後も、同じ clangd の間は飛べた）
- 限界 2: clangd を起動するたびに、そのリポのインデックスを裏で作り直す（作る時は写しで読み、起動時の「変わったか」の確認はディスクの CP932 で読むため、毎回「変わった」になる）。その間も前のインデックスで飛べるが、CPU を使う
- 限界 3: 写すのはリポの中だけ。リポの外の include フォルダ（別の場所の共通ライブラリなど）にある CP932 のヘッダは、今までどおり読み違える
- Neovim を開いていない間にソースが変わると（git pull など）、次に Neovim で C/C++ を開くかフォーカスが戻るまで写しは古いまま
- 仕組みの詳細は `tools/cp932/Utf8Mirror.cs` の冒頭。手で使う時は `tools\bin\utf8-mirror.exe enable|sync|disable <リポ>`・`status`

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
<vault>/.obsidian.vimrc        写し（install.ps1 が上書き）◀─ obsidian/vimrc
<vault>/.obsidian/hotkeys.json  リポの外（Obsidian でキーを付けていないコマンドだけ install.ps1 が足す）◀─ obsidian/hotkeys.json
<vault>/.obsidian/plugins/dotfiles-vim/  写し（install.ps1 が上書き）◀─ obsidian/plugins/dotfiles-vim/・tools/bin/ime.exe
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
├── obsidian/                hotkeys.json・vimrc・plugins/dotfiles-vim（LazyVim と同じキー・モードの表示・今の行の色・相対の行番号・ヤンクの光・IME。tools/Install-ObsidianKeys.ps1 が vault に入れる）
├── tools/file-suggest/      FileSuggest.cs（→ bin/file-suggest.exe・Claude Code の @ の候補に note/ を足す）
├── wsl/                     install.sh・osc7.sh / osc7.zsh（現在地の通知）・aliases.sh
├── nvim/                    LazyVim/starter が元
│   ├── lua/config/          options・keymaps・autocmds の上書きと、
│   │                        encoding・ime・winpath・vault（紫の表示）・machine（~/.dotfiles.json を読む）・jump（Ctrl+Enter）・newnote（新規ノートの場所）・wezterm・
│   │                        clangd_profile（clangd がどの構成で解析しているか）・utf8_mirror（CP932 のソースを clangd に UTF-8 で見せる）・
│   │                        call_tree（呼び出しの階層のツリー）
│   ├── lua/plugins/         encoding・obsidian・snacks・clangd・lazymsbuild・colorscheme・gitsigns・call_tree
│   ├── lazy-lock.json       プラグインの版の固定
│   └── lazyvim.json         入れた extras
├── tools/                   Survey-Encoding.ps1・Install-Lazymsbuild.ps1・Install-MsbuildExtractor.ps1・Install-AiAgents.ps1・
│                            ime/Ime.cs・cp932/Cp932ToUtf8.cs・cp932/Utf8Mirror.cs（→ bin/*.exe・git 管理外）
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
- Obsidian のモードの表示・今の行の色・相対の行番号・ヤンクの光・IME・`Ctrl+o/i` は、設定 → コミュニティプラグインで Vim like Neovim (dotfiles) を無効化して `<vault>/.obsidian/plugins/dotfiles-vim` を消し、設定 → ホットキーでその 2 つのコマンドのキーを消す
- Obsidian のキーは、設定 → エディタで Vim キーバインドを切り、設定 → ホットキーで `obsidian/hotkeys.json` の `editor:` の 7 つのコマンドを既定に戻し、Vimrc Support を無効化して `<vault>/.obsidian.vimrc` を消す
- CP932 の写しは、使っているリポごとに `tools\bin\utf8-mirror.exe disable <リポ>`（一覧は `utf8-mirror status`）。`%LOCALAPPDATA%\clangd\config.yaml` の節と `%LOCALAPPDATA%\utf8-mirror` の写しが消える
- lazymsbuild は `%LOCALAPPDATA%\Programs\lazymsbuild` を消し、ユーザーの PATH からその行を外す（状態は `%LOCALAPPDATA%\lazymsbuild`、抽出ツールは `%LOCALAPPDATA%\msbuild-extractor`）
- vault 関係は `~/.claude/settings.json` の `hooks.PreToolUse` から `note-guard.ps1` を呼ぶ 3 項目・`fileSuggestion`・`permissions.additionalDirectories` の vault を消し（`.bak-*` があれば戻す）、`~/.copilot/hooks/note-guard.json` を消す。CSS は Obsidian の設定で切って `<vault>/.obsidian/snippets/vault-task-status.css` を消す
- AI エージェントは `cmd /c rmdir %USERPROFILE%\.claude\skills\msbuild-cpp` と `cmd /c rmdir %USERPROFILE%\.copilot\skills\msbuild-cpp`（`vault-note` も同じ・junction だけ外れる）、`~/.copilot/lsp-config.json` から `clangd`・`rust-analyzer` の項目を消す（`.bak-*` があれば戻す）、`claude plugin uninstall clangd-lsp@claude-plugins-official`（`rust-analyzer-lsp` も）、`rustup component remove rust-analyzer`
- `~/.dotfiles.json` を消す
