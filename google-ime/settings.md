# Google 日本語入力の設定（このPCの正本）

`%APPDATA%\LocalLow\Google\Google Japanese Input\config1.db` の中身を人が読める形にしたもの。
**復元に使うのは `config1.db`**（この md は何が入っているかの説明）。手順 → `../README.md` の「Google 日本語入力」。

- 取り込み元: win-main（6r1ntr-y52o）・Google 日本語入力 3.33.6130.0 / Windows 11 (26300)
- 取り込み日: 2026-10-05（`Export-GoogleIme.ps1`）

## 既定と違うところ（＝操作感を決めている設定）

| 設定 | 値 | 何が変わるか |
|---|---|---|
| キー設定の選択（`session_keymap`） | **カスタム** | 下の `keymap.txt` を使う。既定は MS-IME 準拠 |
| カスタムキーマップ（`custom_keymap_table`） | `keymap.txt` | **F13 = IME OFF・F14 = IME ON**（下記） |
| 絵文字変換（`use_emoji_conversion`） | **ON** | 「えもじ」等から絵文字を候補に出す。既定は OFF |

他の項目（ローマ字入力・句読点「、。」・記号「「」・」・スペースは入力モードに従う・
学習あり・候補の番号キー 1〜9・候補 3 件・テンキーは半角・\\ は「¥」・
日付/単漢字/記号/数字/顔文字/計算機/カタカナ英数/郵便番号/つづり補正の変換 ON・
履歴/辞書/リアルタイム変換の予測 ON・モード表示 ON）は**すべて Google 日本語入力の既定**。
ローマ字テーブルのカスタマイズ（`custom_roman_table`）は**無し**＝既定のローマ字表。

## keymap.txt は「MS-IME 準拠」からの差分だけ

`keymap.txt` は MS-IME 準拠プリセット（mozc の `data/keymap/ms-ime.tsv`）と比べて 9 行だけ違う。
つまり**操作感の本体は MS-IME 準拠で、IME の ON/OFF の付け方だけを自分用にしてある**。

追加（IME の ON/OFF を独立した 2 キーに割り当てる＝トグルを使わない）:

```
Composition     F13  IMEOff     Composition     F14  IMEOn
Conversion      F13  IMEOff     Conversion      F14  IMEOn
Precomposition  F13  IMEOff     Precomposition  F14  IMEOn
                                DirectInput     F14  IMEOn
```

変更: `DirectInput F13 IMEOn` → `DirectInput F14 IMEOn`
（IME が切れている状態で F13 を押しても何も起きない＝「F13 は必ず OFF」になる）

削除: `Conversion F1 ReportBug` ・ `Conversion F3 ReportBug`（変換中の F1/F3 でバグ報告画面が出るのを止める）

### なぜ F13 / F14 か

macOS の「英数 / かな」と同じ**押した方向が決まっているキー**にするため。トグル（半角/全角）は
「今どちらか」を覚えていないと外すので、ノーマルモードに戻る操作と相性が悪い。
F13/F14 はキーボード側（Keychron の QMK レイヤ）から送る。この表は**その受け側**。

> 💡 nvim は Esc で自動的に IME を切る（`../nvim/lua/config/ime.lua`）ので、
> F13 は「手で確実に切りたい時」の保険として残る。

## 入っていないもの（意図的）

ユーザー辞書・学習履歴・予測履歴（`history.db`・`segment.db`・`boundary.db`・`cform.db`）は
**入れない**。個人の入力内容そのもので、公開リポジトリに置くものではない。
新しいPCでは学習し直す（`config1.db` だけで操作感は再現できる）。
