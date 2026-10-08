# キーボードの設定（このPCの正本）

US（ANSI）配列の **Keychron B1 Pro** を、日本語版 Windows で US 配列として使うための設定。
手順 → `../README.md` の「キーボード」。

- 取り込み元: win-main（6r1ntr-y52o）・Windows 11 (26300)
- 取り込み日: 2026-10-08（キーマップの実体は Launcher で 2026-10-03 13:50 に書き出したもの）

## 設定は 2 層ある

| 層 | 何が決まる | 実体の置き場 | 持ち運び |
|---|---|---|---|
| **キーボードの中** | キーマップ（Caps=Ctrl・F13/F14 ほか） | キーボードの不揮発メモリ。編集は [Keychron Launcher](https://launcher.keychron.com/)（WebHID・ブラウザ） | キーボードごと動く＝**PC を変えても付いてくる** |
| **Windows の中** | **物理配列の解釈**（US 101 か JIS 106 か） | `HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters`（全ユーザー共通） | **PC ごとに要設定**＝`Set-UsPhysicalLayout.ps1` |

つまり新しい PC で要るのは下の層だけ。上の層はバックアップとして置いてある（キーボードを初期化した時・買い替えた時用）。

## Windows 側（`Set-UsPhysicalLayout.ps1`）

入力言語は日本語（`HKCU\Keyboard Layout\Preload` = `00000411`・日本語版 Windows の既定なので触らない）のまま、
**物理配列だけ US 101 として解釈させる**。これをやらないと記号の位置が JIS 配列として読まれて全部ずれる。

| 値 | US にする（このリポの設定） | 日本語版の既定 |
|---|---|---|
| `LayerDriver JPN` | **kbd101.dll** | kbd106.dll |
| `OverrideKeyboardIdentifier` | **PCAT_101KEY** | PCAT_106KEY |
| `OverrideKeyboardSubtype` | **0** | 2 |
| `OverrideKeyboardType` | 7 | 7 |

- `HKLM` なので**管理者権限**と**再起動**が要る
- 変更前に `reg export` で `%LOCALAPPDATA%\dotfiles-windows\i8042prt-Parameters-<日時>.reg` に退避する（戻せる）
- `-Revert` で上表の右側（日本語版の既定）に戻す。`-Show` は読むだけ（管理者権限は不要）
- このキーは PS/2 ポートのドライバのものだが、**JPN レイヤの配列判定は USB/Bluetooth のキーボードにも効く**（Windows の仕様）
- スキャンコードの入れ替え（`HKLM\...\Control\Keyboard Layout` の `Scancode Map`）は**使っていない**。キーの入れ替えはキーボード側でやる

## キーボード側（`keymap/B1-Pro-ANSI.json`）

Launcher の「書き出し」で出るファイルそのまま。`id` = `0x3434071A`（VID 0x3434 / PID 0x071A = B1 Pro ANSI）。
**4 レイヤー × 154 キー**。B1 Pro は Keychron 製 ZMK フォークで動くが、キーコードの番号は QMK と同じ体系。

| レイヤー | 何 |
|---|---|
| L0 / L1 | Mac（本体スイッチが Mac 側）・ベース / Fn |
| **L2 / L3** | **Windows**・ベース / Fn ← 普段使うのはこちら |

既定から変えてある所（マトリクス座標で示す。この板は膜シートで行列が物理配置と対応しないため）:

| 座標 | L2（Win ベース） | L3（Win Fn） | 何のため |
|---|---|---|---|
| `r5c17` ＝ Caps Lock | **LCtrl** | CapsLock | Caps を Ctrl にする。本来の CapsLock は Fn+Caps に残す |
| `r4c0` ＝ スペース右 | **F14** | — | **IME ON**。受け側 → `../google-ime/keymap.txt` |
| `r6c17` ＝ スペース左 | **F13** | — | **IME OFF**。同上 |
| F 列 | F1〜F12 を直接 | メディア / 輝度 | Win 層では F キー優先（Mac 層 L0 は逆で、メディアが直接） |

> `r4c0` / `r6c17` は Mac 層（L0）で かな（`LANG1`）/ 英数（`LANG2`）が載っている 2 キー。
> macOS の「英数 / かな」と同じ**押した方向が決まっている 2 キー**にするのが狙いで、
> Windows 側ではそれを F13 / F14 で表現している（理由 → `../google-ime/settings.md`）。

`0x7E00`〜（`QK_KB_0`〜）の値は Keychron 独自キー（Bluetooth の切替・バックライト・電池残量など）。
意味は Launcher の画面で確認する。

### 2026-03-09 → 2026-10-03 で変えたこと

| レイヤー | 座標 | 前 | 後 |
|---|---|---|---|
| L2 (Win) | r6c17 | 無変換（`INT5`） | **F13**（IME OFF） |
| L2 (Win) | r4c0 | 変換（`INT4`） | **F14**（IME ON） |
| L2 (Win) | r1c2 | メニュー（`APP`） | F1 |
| L3 (Win Fn) | r5c17 | — | **CapsLock**（Fn+Caps で取り戻す） |
| L0 (Mac) | r6c17 / r4c0 | Keychron 独自キー | **英数 / かな** |
| L0 (Mac) | r5c17 / r3c10 | CapsLock / 独自キー | 独自キー / **LCtrl** |

## 未決: Caps を「単押し Esc・長押し Ctrl」にする

やりたい形は Mod-Tap（`MT(MOD_LCTL, KC_ESC)` ＝ `CTL_T(KC_ESC)`・生値 **`8489`** = `0x2129`）。

- Launcher のコードには **Mod-Tap のカテゴリが実装されている**（`main.js` の `generateKeysTab()` に `"modtap"`）。
  ただし B1 Pro の機種定義でそのタブが出るかは**未確認**。Launcher で Caps を選んで左のカテゴリを見れば分かる
- 出れば L2 の `r5c17` を差し替えるだけ。焼く前に `Export-KeychronKeymap.ps1` で今の状態を取り込んでおく
- 出なければ: ①自前 ZMK を焼く（Launcher と 2.4GHz を失う。参考 → `goyamamoto/zmk-keychron-b1-pro`。ただし
  想定 PID が `0x0711` でこの実機の `0x071A` と違うので要確認）②PC 側に `kanata` 等を常駐（可逆だが常駐が増える。
  その場合は先に `r5c17` を素の CapsLock に戻す＝二重変換を避ける）
- 副作用: Esc は「離した時」に出る・Esc の長押しリピートが消える

## 入っていないもの（意図的）

- **PowerToys Keyboard Manager のリマップ**: 空（0 件）。キーの入れ替えはキーボード側でやるので使わない
- **AutoHotkey 等の常駐リマッパー**: 入れていない
- `Scancode Map`: 使っていない（上記）
