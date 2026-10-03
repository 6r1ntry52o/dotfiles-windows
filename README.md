# dotfiles-windows

Windows 用の設定置き場。今は WezTerm だけ。Mac 用は別リポ [`dotfiles`](https://github.com/6r1ntry52o/dotfiles)。

## 新しい PC に入れる

```powershell
git clone https://github.com/6r1ntry52o/dotfiles-windows.git $HOME\dev_repository\dotfiles-windows
powershell -ExecutionPolicy Bypass -File $HOME\dev_repository\dotfiles-windows\install.ps1
```

`install.ps1` がすること（何度流してもよい）:

1. winget で WezTerm と PowerShell 7 を入れる（入っていれば何もしない。`-SkipPackages` で飛ばせる）
2. `~/.wezterm.lua` に、このリポの `wezterm/wezterm.lua` を読み込む 5 行のスタブを書く
   - 既存の `~/.wezterm.lua` が自分の物なら `.bak-日時` に退避してから上書き
   - シンボリックリンクではないので管理者権限は不要。clone 先はどこでもよい（移動したら再実行）

## 設定を変える・同期する

- 編集するのは `wezterm/*.lua`。保存すると WezTerm が自動で再読み込みする（手動は `Ctrl+Shift+R`）
- 他の PC へは `git push` → 向こうで `git pull` だけ

## 構成

```
install.ps1            セットアップ
wezterm/wezterm.lua    本体（見た目・既定シェル・タブ）
wezterm/keybinds.lua   キーバインド
```

- 既定シェル: PowerShell 7（無ければ Windows PowerShell 5.1 に落ちる）。ランチャーに 5.1・Git Bash・WSL も出る
- フォント: HackGen Console（https://github.com/yuru7/HackGen ・手動で入れる。未導入の PC では同梱の JetBrains Mono に落ちる）
- タイトルバーなし: 終了は `Alt+F4`、移動はタブバーの空き部分をドラッグ

## キーバインド

既定のキーは無効化してある。Leader = `Ctrl+Q`（2 秒以内に次のキー）。

| キー | 動作 |
|---|---|
| `Ctrl+Shift+T` / `Ctrl+Shift+W` | タブを開く / 閉じる |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | 次 / 前のタブ |
| `Alt+1`〜`8` / `Alt+9` | N 番目 / 最後のタブ |
| `Leader {` / `Leader }` | タブを左 / 右へ移動 |
| `Leader d` / `Leader r` | 上下 / 左右に分割 |
| `Leader h/j/k/l` | ペイン移動 |
| `Leader x` / `Leader z` | ペインを閉じる / ズーム |
| `Leader s` → `h/j/k/l` | ペインのサイズ変更（`Enter` で抜ける） |
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

`~/.wezterm.lua` を消す（退避した `.bak-*` があれば戻す）。
