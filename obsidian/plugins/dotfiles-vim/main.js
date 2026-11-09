// Obsidian の Vim モードを Neovim（LazyVim）に寄せる。dotfiles-windows の nvim と同じ動きを 8 つ足す
// （もう 1 つ、今いる分割のカーソルの行を塗るのは styles.css でやる。帯の色は今のモードの色で、
// そのために編集画面（.cm-editor）に data-dotfiles-vim-mode を付ける）。
//
//   1. 今のモードをステータスバーの左端に出す（NORMAL・INSERT・VISUAL・V-LINE・V-BLOCK・REPLACE・
//      COMMAND）。色は nvim の lualine（kanagawa wave）と同じ（styles.css）。その右に、押しかけのキー
//      （<Space>s・2d など。nvim の showcmd）を出す。中身は Obsidian の Vim が持つ status（押したキーを
//      足していき、コマンドが終わると空にする）
//   2. INSERT 以外の間は IME を必ず OFF にする（nvim/lua/config/ime.lua の Obsidian 版）。
//      Esc で戻った直後に IME が ON のままだと、h/j/k/l や dd が IME に食われて
//      「ひじくる」のような未確定文字になる＝ノーマルモードのキーが1つも通らない
//   3. ノーマルモードの Ctrl+O / Ctrl+I で、前・次に開いていた所へ戻る・進む（nvim のジャンプリストの
//      代わりに Obsidian のタブの履歴）。それ以外の所では今までどおりクイックスイッチャー・斜体
//   4. 行番号を今の行からの距離にする（nvim の number + relativenumber。今の行だけ本来の番号）。
//      行番号そのものは Obsidian の設定（エディタ → 行番号を表示）で出す
//   5. ファイルエクスプローラを hjkl で動かす（LazyVim の explorer: j/k 上下・h 閉じる / 親へ・
//      l フォルダの開閉 / ファイルを開く）。エクスプローラに入った時も IME を切る（ノーマルモードと同じ扱い）
//   6. Ctrl+矢印で分割の大きさを変える（LazyVim の <C-Up>/<C-Down>＝高さ ±・<C-Left>/<C-Right>＝幅 ∓/±）。
//      INSERT の編集画面と入力欄では元の動き（単語の移動など）のまま
//   7. Space のリーダーを編集画面の外でも効かせる（ファイルエクスプローラ・閲覧表示・新しいタブの画面）。
//      編集画面の中は Vim（vimrc の nmap）が受ける。キーの表は vimrc の exmap と nmap <Space>… から作るので、
//      キーを足すのは vimrc だけでよい
//   8. ヤンクした所を一瞬光らせる（nvim の vim.hl.on_yank。LazyVim が TextYankPost で呼ぶ）。色は styles.css
//
// 9 は nvim の真似ではなく守り。ノートを、別のノートの中身で丸ごと上書きする保存を止める。2026-11-07〜08 に
// core の vault で 4 回、開いているノートが別のノートの（古い版の）中身に入れ替わって保存された（Vim を
// 入れた日から・きっかけは未確定）。中身は、同じファイルを開いている別のタブから届いていた（Obsidian は
// 1 つのタブで変わった中身を quick-preview で他のタブに配り、配られた側は undo できる「set」として入れる）。
// どこから来ても保存は vault.modify を通るので、そこで見る（ファイルの外からの書き換えと Sync は通らない）。
//   止める: 前の中身の 5 割を超える行が入れ替わり、新しい中身が別のノートの今の中身か、ファイルの復元
//           （File recovery・既定で 7 日）に残る別のノートの版と、空白を除いて同じ（1 行の途中の改行が
//           1 つ増えただけの写しもあった）。作って 10 分のうちのノートは見ない（新しいノートに写すのは止めない）
//   止めたら: 書かずに、そのファイルを開いているタブをディスクの中身に戻して知らせる（戻す前の中身は u で
//           出る）。わざとなら、コマンド Allow the next overwrite… の後に保存し直す
//   残す: 止めた時と、どれとも一致しないが丸ごと入れ替わった時に、直前のキー・タブの切り替え・配られた中身の
//         大きさを %LOCALAPPDATA%\dotfiles-vim\overwrite.jsonl に 1 行で（きっかけを突き止めるため）。
//         INSERT と入力欄で打った文字は残さない（· にする）。ノートの文も残さない
//
// （今のタブグループの今のタブをアクセントの色にするのは styles.css だけでやる）
//
// 正本: dotfiles-windows/obsidian/plugins/dotfiles-vim。install.ps1 の 8c が
// <vault>/.obsidian/plugins/dotfiles-vim/ に写し、隣に tools/bin/ime.exe も置く
// （写しは上書きするので、直すのはリポの方）。ime.exe は前面のウィンドウ（＝Obsidian）の IME を
// 外から OFF にする（tools/ime/Ime.cs）。ime.exe が無い PC（Sync でプラグインだけ届いた）では 2 だけ動かない。
//
// IME を切る時（nvim と同じ）:
//   INSERT（置換を含む）を抜けた時 … InsertLeave
//   編集画面にフォーカスが入った時 … CmdlineLeave（/ や : の入力欄から戻った）と、別のペインや
//                                    サイドバーから入った時
//   Obsidian に戻ってきた時       … FocusGained
//   ノートを開いた時・有効にした時 … VimEnter
// INSERT 中の編集画面は触らない（日本語を打っている最中）。INSERT に入っても ON には戻さない
// ので、日本語を打つ時は F14 を押す。
//
// Ctrl+O / Ctrl+I をコマンドの中で分けるのは、Obsidian がホットキーを編集画面より先に拾う
// （window の capture で受けて止める）ので、vimrc の nmap には届かないため。キーは obsidian/hotkeys.json に
// 書く。自分で付けたキーは既定のキー（クイックスイッチャーの Ctrl+O・斜体の Ctrl+I）より先に試される。
'use strict';

const { MarkdownView, Notice, Plugin } = require('obsidian');
const { Compartment, StateEffect, StateField } = require('@codemirror/state');
const { Decoration, EditorView, lineNumbers } = require('@codemirror/view');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

// ステータスバーに出す名前（lualine と同じ）
const MODE_LABELS = {
  normal: 'NORMAL',
  insert: 'INSERT',
  visual: 'VISUAL',
  'visual-line': 'V-LINE',
  'visual-block': 'V-BLOCK',
  replace: 'REPLACE',
  command: 'COMMAND',
};

// Ctrl+矢印 1 回で動かす幅（px）と、分割・サイドバーの最小の幅（Obsidian がドラッグで止める 200px と同じ）
const RESIZE_STEP = 40;
const MIN_PANE = 200;

// 編集画面の外で Space のリーダーを受ける画面（data-type）。Canvas や Excalidraw は Space を押しながらの
// ドラッグで動かすので入れない。ファイルエクスプローラは木の scope で受ける（hookExplorers）
const LEADER_VIEWS = ['markdown', 'empty'];
const MODIFIER_KEYS = ['Shift', 'Control', 'Alt', 'Meta', 'CapsLock'];

// vimrc の exmap <名前> obcommand <id> と nmap <Space><キー> :<名前><CR> から、<Space> の後のキー → id
function parseLeader(vimrc) {
  const ex = {};
  const keys = {};
  for (const line of vimrc.split(/\r?\n/)) {
    const exmap = line.match(/^\s*exmap\s+(\w+)\s+obcommand\s+(\S+)/);
    if (exmap) {
      ex[exmap[1]] = exmap[2];
      continue;
    }
    const nmap = line.match(/^\s*n?map\s+<Space>(\S+)\s+:(\w+)<CR>\s*$/);
    if (nmap) {
      keys[nmap[1]] = nmap[2];
    }
  }
  return Object.fromEntries(Object.entries(keys).filter(([, name]) => ex[name]).map(([k, name]) => [k, ex[name]]));
}

// Ctrl+矢印 → [向き, 大きくするか]
const RESIZE_KEYS = {
  ArrowUp: ['y', true],
  ArrowDown: ['y', false],
  ArrowLeft: ['x', false],
  ArrowRight: ['x', true],
};

function cursorLine(state) {
  return state.doc.lineAt(state.selection.main.head).number;
}

// 行番号を今の行からの距離にする。行番号の欄は Obsidian のもの（行番号を切っていれば出ない）をそのまま
// 使い、数字の書き方だけを渡す。lineNumbers() は [書き方の設定, gutters(), 行番号の欄] を返すので、
// 先頭の設定だけ取る（欄まで足すと、行番号を切っていても出てしまう）。Obsidian は書き方を渡して
// いないので、ぶつからない。欄は書き方の設定が変わった時しか書き直さないので、カーソルの行が変わる
// たびに設定を作り直して書き直させる。
function relativeLineNumbers() {
  const numbers = new Compartment();
  const config = () =>
    lineNumbers({
      formatNumber: (n, state) => {
        const cursor = cursorLine(state);
        // 行数より大きい n は欄の幅を決める呼び出し。幅がカーソルで変わらないよう、そのまま返す
        return String(n > state.doc.lines || n === cursor ? n : Math.abs(n - cursor));
      },
    })[0];
  return [
    numbers.of(config()),
    EditorView.updateListener.of((update) => {
      if (cursorLine(update.startState) !== cursorLine(update.state)) {
        update.view.dispatch({ effects: numbers.reconfigure(config()) });
      }
    }),
  ];
}

// ヤンクした所を光らせる時間（vim.hl.on_yank の既定と同じ）と、光らせる範囲を入れ替える effect（空なら消す）
const YANK_MS = 150;
const setYank = StateEffect.define();
const yankMark = Decoration.mark({ class: 'dotfiles-vim-yank' });
const yankField = StateField.define({
  create: () => Decoration.none,
  update(marks, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setYank)) {
        return Decoration.set(effect.value.map(({ from, to }) => yankMark.range(from, to)), true);
      }
    }
    return marks.map(tr.changes);
  },
  provide: (field) => EditorView.decorations.from(field),
});

// 9 の上書きの守り: 見る大きさ（空白を除いた文字数）・残っていれば止めない行の割合・見ない新しいノートの
// 若さ・わざとの上書きを通す間・きっかけを探すために覚えておく出来事の数
const GUARD_MIN_CHARS = 20;
const GUARD_KEEP_RATIO = 0.5;
const GUARD_NEW_FILE_MS = 10 * 60 * 1000;
const GUARD_ALLOW_MS = 60 * 1000;
const GUARD_RECENT = 80;
const GUARD_LOG = path.join(process.env.LOCALAPPDATA || require('os').tmpdir(), 'dotfiles-vim', 'overwrite.jsonl');

// 空白（改行・全角の空白を含む）を除いた中身。改行が 1 つ増えただけの写しも同じと見る
function squash(text) {
  return text.replace(/\s+/g, '');
}

// 前の中身の行（空行は数えない）のうち、新しい中身に残っている割合。前が空なら 0
function keptRatio(before, after) {
  const left = new Map();
  for (const line of after.split(/\r?\n/)) {
    const t = line.trim();
    if (t) {
      left.set(t, (left.get(t) || 0) + 1);
    }
  }
  let total = 0;
  let kept = 0;
  for (const line of before.split(/\r?\n/)) {
    const t = line.trim();
    if (!t) {
      continue;
    }
    total++;
    const n = left.get(t);
    if (n) {
      kept++;
      left.set(t, n - 1);
    }
  }
  return total ? kept / total : 0;
}

module.exports = class DotfilesVimPlugin extends Plugin {
  onload() {
    const ime = path.join(this.app.vault.adapter.getBasePath(), this.manifest.dir, 'ime.exe');
    this.ime = fs.existsSync(ime) ? ime : null;
    if (!this.ime) {
      console.warn(`dotfiles-vim: ${ime} が無いので IME は切らない（dotfiles の install.ps1 を流すと入る）`);
    }
    // Vim の口（編集画面ごと）→ 付けたハンドラ。外す時に使う
    this.hooked = new Map();
    this.modeEl = this.addStatusBarItem();
    this.modeEl.addClass('dotfiles-vim-mode');
    this.keysEl = this.addStatusBarItem();
    this.keysEl.addClass('dotfiles-vim-keys');

    // repeatable: 押しっぱなしの 2 回目からもこのコマンドを試させる（でないと既定のキーの方に落ちる）
    this.addCommand({
      id: 'back',
      name: 'Back in Normal mode (Quick switcher elsewhere)',
      repeatable: true,
      callback: () => this.runByMode('app:go-back', 'switcher:open'),
    });
    this.addCommand({
      id: 'forward',
      name: 'Forward in Normal mode (Italic elsewhere)',
      repeatable: true,
      callback: () => this.runByMode('app:go-forward', 'editor:toggle-italics'),
    });
    this.registerEditorExtension(relativeLineNumbers());
    // 今光らせている { view, timer }
    this.yanked = null;
    this.registerEditorExtension(yankField);
    this.hookYank();
    // Ctrl+矢印はホットキーにしない。Obsidian はホットキーのコマンドが例外を投げた時しかキーを他へ回さず、
    // INSERT や入力欄で何もしなくてもキーを止めてしまう（単語の移動が効かなくなる。本体のコードで確認）。
    // ここは Obsidian のキーの処理（同じ window の capture・先に登録）の後に来る。エクスプローラの中は
    // hookExplorers が足したキーが先に受けて止めるので、ここでは何もしない（defaultPrevented）
    this.registerDomEvent(window, 'keydown', (ev) => this.onResizeKey(ev), { capture: true });
    // 編集画面の外の Space のリーダー。null＝待っていない・文字列＝Space の後に押したキー
    this.leader = null;
    this.leaderMap = {};
    this.loadLeader();
    this.registerDomEvent(window, 'keydown', (ev) => this.onLeaderKey(ev), { capture: true });

    // ファイルエクスプローラの木（scope）→ 足したキー。外す時に使う
    this.scoped = new Map();
    this.registerDomEvent(document, 'focusin', (ev) => {
      // Space の後に別の所へ移ったら、リーダーはやめる（移った先の最初のキーを食べないように）
      this.leader = null;
      this.offUnlessInsert(ev.target);
      this.showMode();
    });
    this.registerDomEvent(window, 'focus', () => this.offUnlessInsert(document.activeElement));
    this.registerEvent(this.app.workspace.on('file-open', () => this.offUnlessInsert(document.activeElement)));
    this.registerEvent(this.app.workspace.on('active-leaf-change', () => this.showMode()));
    this.registerEvent(
      this.app.workspace.on('layout-change', () => {
        this.showMode();
        this.hookExplorers();
      })
    );
    this.app.workspace.onLayoutReady(() => {
      this.offUnlessInsert(document.activeElement);
      this.showMode();
      this.hookExplorers();
    });
    this.guardOverwrite();
  }

  onunload() {
    cancelAnimationFrame(this.frame);
    this.clearYank();
    for (const cm of this.hooked.keys()) {
      this.unhook(cm);
    }
    for (const [scope, handlers] of this.scoped) {
      for (const handler of handlers) {
        scope.unregister(handler);
      }
    }
  }

  // 文字を打っている所か: INSERT の編集画面・入力欄（名前の変更・検索・: の入力欄など）
  isTyping(el) {
    const cm = this.vimOf(el);
    if (cm) {
      return !!cm.state.vim.insertMode;
    }
    return el instanceof HTMLElement && (el.isContentEditable || el.matches('input, textarea, select'));
  }

  // ファイルエクスプローラの木の scope に hjkl と Ctrl+矢印を足す。木は矢印と Ctrl+矢印（動いて開く）を
  // もう持っていて、scope は登録した順に試すので、足した分を先頭に回す（Ctrl+矢印もここで分割の大きさに）。
  // 名前の変更の入力欄の中では何もしない（true を返すと、Obsidian は止めずに入力欄へ渡す）
  hookExplorers() {
    for (const leaf of this.app.workspace.getLeavesOfType('file-explorer')) {
      const tree = leaf.view?.tree;
      const scope = tree?.scope;
      if (!scope || this.scoped.has(scope)) {
        continue;
      }
      // リーダーの途中なら、ここで受けたキーもリーダーの続きにする（Space の後の j などを木に渡さない）
      const key = (modifiers, k, fn) =>
        scope.register(modifiers, k, (ev) => {
          if (this.isTyping(ev.target)) {
            return true;
          }
          // 同じキーは window の onLeaderKey にも来る。そこで 2 回数えないように
          this.consumed = ev;
          if (this.leader !== null) {
            this.leaderKey(ev);
          } else {
            fn(ev);
          }
          return false;
        });
      const handlers = [
        // Space は木では「開く」。LazyVim と同じくリーダーにする（開くのは l と Enter）
        key([], ' ', () => this.startLeader()),
        key([], 'j', (ev) => tree.onKeyArrowDown(ev)),
        key([], 'k', (ev) => tree.onKeyArrowUp(ev)),
        key([], 'h', (ev) => tree.onKeyArrowLeft(ev)),
        key([], 'l', (ev) => this.explorerOpen(tree, ev)),
        ...Object.entries(RESIZE_KEYS).map(([k, [axis, grow]]) => key(['Mod'], k, () => this.resize(axis, grow))),
      ];
      scope.keys = [...handlers, ...scope.keys.filter((k) => !handlers.includes(k))];
      this.scoped.set(scope, handlers);
    }
  }

  // l: フォルダは開閉、ファイルは開く（LazyVim の explorer の l。Enter と同じ）。
  // h は Obsidian の ← のまま: 開いたフォルダは閉じ、ファイルや閉じたフォルダでは親のフォルダを閉じてそこへ
  explorerOpen(tree, ev) {
    const item = tree.focusedItem;
    if (!item || item === tree.root) {
      return;
    }
    if (item.collapsible) {
      item.setCollapsed(!item.collapsed, true);
    } else {
      tree.onKeyOpen(ev);
    }
  }

  async loadLeader() {
    const vimrc = this.app.plugins.plugins['obsidian-vimrc-support'];
    const file = vimrc?.settings?.vimrcFileName || '.obsidian.vimrc';
    try {
      this.leaderMap = parseLeader(await this.app.vault.adapter.read(file));
    } catch (err) {
      console.warn(`dotfiles-vim: ${file} を読めないので、編集画面の外の Space のリーダーは効かない`, err);
    }
  }

  startLeader() {
    this.leader = '';
    this.render();
  }

  // 編集画面の外で Space を受ける。Obsidian のキーの処理（エクスプローラの木を含む）の後に来る
  onLeaderKey(ev) {
    if (ev === this.consumed || MODIFIER_KEYS.includes(ev.key)) {
      return;
    }
    if (this.leader !== null) {
      ev.preventDefault();
      ev.stopPropagation();
      this.leaderKey(ev);
      return;
    }
    if (ev.key !== ' ' || ev.defaultPrevented || ev.isComposing || ev.ctrlKey || ev.altKey || ev.metaKey || ev.shiftKey) {
      return;
    }
    const el = document.activeElement;
    if (this.vimOf(el) || this.isTyping(el) || el?.closest?.('.modal-container, button, a, [role="button"]')) {
      return;
    }
    const content = el?.closest?.('.workspace-leaf-content');
    if (content ? !LEADER_VIEWS.includes(content.dataset.type) : el !== document.body) {
      return;
    }
    ev.preventDefault();
    ev.stopPropagation();
    this.startLeader();
  }

  // Space の後のキー。表に合えば動かし、続きがありそうなら待ち、どれにも合わなければやめる（Vim と同じ・時間切れ無し）
  leaderKey(ev) {
    if (ev.key === 'Escape') {
      this.leader = null;
    } else {
      const keys = this.leader + (ev.key === ' ' ? '<Space>' : ev.key);
      const id = this.leaderMap[keys];
      this.leader = !id && Object.keys(this.leaderMap).some((k) => k.startsWith(keys)) ? keys : null;
      if (id) {
        this.runLeader(id);
      }
    }
    this.render();
  }

  // サイドバー（エクスプローラ）から押した時は、最後に開いていたノートのタブで動かす（分割・タブを閉じる・
  // アウトラインがノートに効くように。分割は今のタブがサイドバーだと Obsidian が受け付けない）
  runLeader(id) {
    const { workspace } = this.app;
    const leaf = workspace.activeLeaf;
    if (leaf && leaf.getRoot() !== workspace.rootSplit) {
      const recent = workspace.getMostRecentLeaf(workspace.rootSplit);
      if (recent) {
        workspace.setActiveLeaf(recent, { focus: true });
      }
    }
    this.app.commands.executeCommandById(id);
  }

  onResizeKey(ev) {
    const target = RESIZE_KEYS[ev.key];
    if (!target || ev.defaultPrevented || ev.isComposing || !ev.ctrlKey || ev.shiftKey || ev.altKey || ev.metaKey) {
      return;
    }
    if (this.isTyping(document.activeElement)) {
      return;
    }
    ev.preventDefault();
    ev.stopPropagation();
    this.resize(...target);
  }

  // 今の分割を、隣（後ろ。最後なら前）とのあいだで RESIZE_STEP px 動かす（nvim の :resize と同じ向き）。
  // サイドバーの中では、幅はサイドバーの幅。分割が 1 列だけの時の幅は、開いているサイドバーを隣として動かす
  // （nvim で explorer が左にある時と同じ）。
  resize(axis, grow, leaf = this.app.workspace.activeLeaf) {
    const { workspace } = this.app;
    if (!leaf) {
      return;
    }
    const delta = grow ? RESIZE_STEP : -RESIZE_STEP;
    const root = leaf.getRoot();
    if (axis === 'x' && (root === workspace.leftSplit || root === workspace.rightSplit)) {
      return this.resizeSidebar(root, delta);
    }
    const direction = axis === 'x' ? 'vertical' : 'horizontal';
    for (let item = leaf.parent; item?.parent; item = item.parent) {
      const split = item.parent;
      if (split.direction === direction && split.children.length > 1) {
        return this.resizeInSplit(split, item, delta);
      }
    }
    if (axis === 'x') {
      const side = [workspace.leftSplit, workspace.rightSplit].find((s) => !s.collapsed);
      if (side) {
        this.resizeSidebar(side, -delta);
      }
    }
  }

  // Obsidian がドラッグの終わりにするのと同じく、px で決めて割合（dimension）にして入れる
  resizeInSplit(split, item, delta) {
    const { children } = split;
    const sizes = children.map((child) => split.getElSize(child.containerEl));
    const i = children.indexOf(item);
    const j = i < children.length - 1 ? i + 1 : i - 1;
    const size = Math.min(Math.max(sizes[i] + delta, MIN_PANE), sizes[i] + sizes[j] - MIN_PANE);
    if (size <= 0) {
      return;
    }
    sizes[j] -= size - sizes[i];
    sizes[i] = size;
    const total = sizes.reduce((a, b) => a + b, 0);
    children.forEach((child, k) => child.setDimension((sizes[k] / total) * 100));
    this.app.workspace.requestResize();
    this.app.workspace.requestSaveLayout();
  }

  resizeSidebar(side, delta) {
    if (side.collapsed) {
      return;
    }
    const max = this.app.workspace.containerEl.clientWidth - MIN_PANE;
    side.setSize(Math.min(Math.max(side.size + delta, MIN_PANE), max));
    this.app.workspace.requestResize();
    this.app.workspace.requestSaveLayout();
  }

  // 帯の色（styles.css）のために、編集画面にモードを付ける
  markMode(cm, mode) {
    const dom = cm.cm6?.dom;
    if (dom) {
      dom.dataset.dotfilesVimMode = mode;
    }
  }

  // el が編集画面の本文なら、その Vim の口（CodeMirror 5 互換・state.vim を持つ）。表のセルも含む。
  // 本文でない（/ の入力欄・サイドバー）・Vim モードでない時は undefined
  vimOf(el) {
    const content = el instanceof Element ? el.closest('.cm-content') : null;
    const view = content ? EditorView.findFromDOM(content.closest('.cm-editor')) : null;
    const cm = view?.cm;
    return cm?.state?.vim ? cm : undefined;
  }

  // モードを出す編集画面: フォーカスのある編集画面、無ければ今のノートの編集画面（閲覧表示なら無し）
  activeVim() {
    const focused = this.vimOf(document.activeElement);
    if (focused) {
      return focused;
    }
    const view = this.app.workspace.getActiveViewOfType(MarkdownView);
    const cm = view?.getMode() === 'source' ? view.editMode?.editor?.cm?.cm : undefined;
    return cm?.state?.vim ? cm : undefined;
  }

  modeOf(cm) {
    const { vim } = cm.state;
    if (cm.state.dialog) {
      return 'command'; // / や : の入力欄が開いている
    }
    if (vim.insertMode) {
      return cm.state.overwrite ? 'replace' : 'insert';
    }
    if (vim.visualMode) {
      return vim.visualBlock ? 'visual-block' : vim.visualLine ? 'visual-line' : 'visual';
    }
    return 'normal';
  }

  // 状態を読むのは、Vim がキーの処理を終えた後（次の描画の前）にする。続けて何度呼ばれても 1 回で済む
  showMode() {
    if (this.frame) {
      return;
    }
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.render();
    });
  }

  render() {
    const cm = this.activeVim();
    // INSERT 中の status には打った文字もたまっていくので、ノーマルとビジュアルの時だけ出す。
    // 編集画面の外のリーダーの途中なら、それを出す
    let keys = this.leader !== null ? '<Space>' + this.leader : '';
    if (cm) {
      this.hook(cm);
      const mode = this.modeOf(cm);
      this.modeEl.setText(MODE_LABELS[mode]);
      this.modeEl.dataset.mode = mode;
      this.markMode(cm, mode);
      if (!keys && (mode === 'normal' || mode.startsWith('visual'))) {
        keys = cm.state.vim.status || '';
      }
    }
    this.modeEl.toggle(!!cm);
    this.keysEl.setText(keys);
    this.keysEl.toggle(keys !== '');
  }

  offUnlessInsert(el) {
    const cm = this.vimOf(el);
    if (!cm) {
      // ファイルエクスプローラも nvim ではノーマルモードの窓（IME が ON だと hjkl が IME に食われる）
      if (el instanceof Element && el.closest('.workspace-leaf-content[data-type="file-explorer"]') && !this.isTyping(el)) {
        this.off();
      }
      return;
    }
    this.hook(cm);
    if (!cm.state.vim.insertMode) {
      this.off();
    }
  }

  hook(cm) {
    if (this.hooked.has(cm)) {
      return;
    }
    // 閉じた編集画面（表のセルは抜けるたびに捨てられる）の分を外す
    for (const old of this.hooked.keys()) {
      if (!old.cm6?.dom?.isConnected) {
        this.unhook(old);
      }
    }
    // INSERT を抜けた時に IME を切る。ノーマルとビジュアルの行き来では呼ばない（ime.exe を起こさない）
    let mode = cm.state.vim.insertMode ? 'insert' : 'normal';
    const onMode = (ev) => {
      const wasInsert = mode === 'insert' || mode === 'replace';
      mode = ev?.mode ?? mode;
      if (wasInsert && mode !== 'insert' && mode !== 'replace') {
        this.off();
      }
      // 今の分割でない編集画面も、帯の色をモードに合わせておく（その分割に移った時のため）
      this.markMode(cm, this.modeOf(cm));
      this.showMode();
    };
    // dialog: / や : の入力欄の開け閉め。vim-keypress・vim-command-done: 押しかけのキーの表示
    const onRender = () => this.showMode();
    cm.on('vim-mode-change', onMode);
    for (const event of ['dialog', 'vim-keypress', 'vim-command-done']) {
      cm.on(event, onRender);
    }
    this.hooked.set(cm, { onMode, onRender });
    this.markMode(cm, this.modeOf(cm));
  }

  unhook(cm) {
    const { onMode, onRender } = this.hooked.get(cm);
    cm.off('vim-mode-change', onMode);
    for (const event of ['dialog', 'vim-keypress', 'vim-command-done']) {
      cm.off(event, onRender);
    }
    if (cm.cm6?.dom) {
      delete cm.cm6.dom.dataset.dotfilesVimMode;
    }
    this.hooked.delete(cm);
  }

  // ヤンク（y の演算子・:yank）は、どれも Vim のレジスタの pushText を通る（Obsidian 本体の lib/codemirror/vim.js）。
  // y の時は、選択がヤンクした範囲になっている（中身を選択から取るため。ブロックのヤンクは選択が複数）ので、
  // それを光らせる。:yank は選択がカーソルのままなので光らない。window.CodeMirrorAdapter.Vim が編集画面
  // （CodeMirror 6）の Vim（CodeMirror.Vim は旧エディタの別物）。pushText はレジスタの表の prototype にある
  hookYank() {
    const controller = window.CodeMirrorAdapter?.Vim?.getRegisterController?.();
    const proto = controller && Object.getPrototypeOf(controller);
    const original = proto?.pushText;
    if (typeof original !== 'function') {
      console.warn('dotfiles-vim: Vim のレジスタが見つからないので、ヤンクした所は光らない');
      return;
    }
    const plugin = this;
    let active = true;
    const pushText = function (registerName, operator, ...rest) {
      const result = original.call(this, registerName, operator, ...rest);
      // "_ はどこにも入れない（nvim も TextYankPost を起こさない）
      if (active && operator === 'yank' && registerName !== '_') {
        plugin.flashYank();
      }
      return result;
    };
    proto.pushText = pushText;
    this.register(() => {
      active = false;
      // 後から他のプラグインが包んでいたら、そのまま残す（戻すとそちらの分も外れる）
      if (proto.pushText === pushText) {
        proto.pushText = original;
      }
    });
  }

  // キーを受けた編集画面（フォーカスのある所）の今の選択を、YANK_MS だけ光らせる
  flashYank() {
    const view = this.activeVim()?.cm6;
    const ranges = view ? view.state.selection.ranges.filter((range) => !range.empty) : [];
    if (!ranges.length) {
      return;
    }
    this.clearYank();
    view.dispatch({ effects: setYank.of(ranges) });
    this.yanked = { view, timer: window.setTimeout(() => this.clearYank(), YANK_MS) };
  }

  clearYank() {
    if (!this.yanked) {
      return;
    }
    const { view, timer } = this.yanked;
    this.yanked = null;
    clearTimeout(timer);
    // 閉じた編集画面は消すまでもない
    if (view.dom.isConnected) {
      view.dispatch({ effects: setYank.of([]) });
    }
  }

  // ノーマルモードの編集画面にフォーカスがある時だけ inNormal、それ以外はこのキーの元の動き
  runByMode(inNormal, otherwise) {
    const cm = this.vimOf(document.activeElement);
    const normal = cm && !cm.state.vim.insertMode && !cm.state.vim.visualMode;
    this.app.commands.executeCommandById(normal ? inNormal : otherwise);
  }

  // 9. vault.modify を包んで、別のノートの中身での丸ごとの上書きを止める。外す時は、間に他のプラグインが
  // 包んでいなければ元に戻す。きっかけを探すための出来事も覚え始める
  guardOverwrite() {
    this.recent = [];
    this.allowUntil = 0;
    this.addCommand({
      id: 'allow-overwrite',
      name: "Allow the next overwrite with another note's text (1 minute)",
      callback: () => {
        this.allowUntil = Date.now() + GUARD_ALLOW_MS;
        new Notice('次の 1 回（1 分のうち）は、別のノートの中身での上書きを止めません。保存し直してください。');
      },
    });
    const { vault } = this.app;
    const modify = vault.modify;
    const plugin = this;
    const guarded = async function (file, data, options) {
      // 呼んだ所は await の前でしか取れない
      const stack = new Error().stack;
      if (await plugin.blockOverwrite(file, data, stack)) {
        return;
      }
      return modify.call(this, file, data, options);
    };
    vault.modify = guarded;
    this.register(() => {
      if (vault.modify === guarded) {
        vault.modify = modify;
      }
    });

    const note = (entry) => {
      this.recent.push({ t: Date.now(), ...entry });
      if (this.recent.length > GUARD_RECENT) {
        this.recent.shift();
      }
    };
    const where = () => ({ leaf: this.app.workspace.activeLeaf?.id, file: this.app.workspace.getActiveFile()?.path });
    this.registerDomEvent(
      window,
      'keydown',
      (ev) => {
        if (MODIFIER_KEYS.includes(ev.key)) {
          return;
        }
        const cm = this.vimOf(ev.target);
        const mods = (ev.ctrlKey ? 'C-' : '') + (ev.altKey ? 'A-' : '') + (ev.metaKey ? 'M-' : '');
        // 打っている文字は残さない（修飾キーの付いたキーと、Esc などの名前のあるキーは残す）
        const text = !mods && ev.key.length === 1 && this.isTyping(ev.target);
        note({ ev: 'key', k: text ? '·' : mods + ev.key, mode: cm ? this.modeOf(cm) : 'ui', ...where() });
      },
      { capture: true }
    );
    this.registerEvent(this.app.workspace.on('file-open', (file) => note({ ev: 'open', ...where(), opened: file?.path })));
    this.registerEvent(this.app.workspace.on('active-leaf-change', () => note({ ev: 'leaf', ...where() })));
    this.registerEvent(
      this.app.workspace.on('layout-change', () => note({ ev: 'layout', leaves: this.app.workspace.getLeavesOfType('markdown').length }))
    );
    // 配られた中身（打つたびに来るので、同じファイルが続く間は 1 つにまとめる）
    this.registerEvent(
      this.app.workspace.on('quick-preview', (file, data) => {
        const last = this.recent[this.recent.length - 1];
        if (last && last.ev === 'preview' && last.path === file?.path) {
          last.t = Date.now();
          last.chars = data.length;
          last.n++;
          return;
        }
        note({ ev: 'preview', path: file?.path, chars: data.length, n: 1, ...where() });
      })
    );
    this.registerEvent(this.app.vault.on('modify', (file) => note({ ev: 'modify', path: file.path })));
    this.registerEvent(this.app.vault.on('rename', (file, old) => note({ ev: 'rename', path: file.path, old })));
  }

  // 止めるなら true。ここで例外が出たら止めない（保存できない方が困る）
  async blockOverwrite(file, data, stack) {
    try {
      if (file.extension !== 'md') {
        return false;
      }
      const before = await this.app.vault.cachedRead(file);
      const after = squash(data);
      if (before === data || after.length < GUARD_MIN_CHARS || after === squash(before)) {
        return false;
      }
      if (keptRatio(before, data) > GUARD_KEEP_RATIO || Date.now() - file.stat.ctime < GUARD_NEW_FILE_MS) {
        return false;
      }
      const from = await this.sameAsOtherNote(file, data, after);
      if (from && Date.now() < this.allowUntil) {
        this.allowUntil = 0;
        this.logOverwrite('allowed', file, before, data, from, stack);
        return false;
      }
      this.logOverwrite(from ? 'blocked' : 'replaced', file, before, data, from, stack);
      if (!from) {
        return false;
      }
      this.restoreFromDisk(file);
      const when = from.ts ? `（${new Date(from.ts).toLocaleString('ja-JP')} の版）` : '';
      new Notice(
        `「${file.basename}」を「${from.path}」${when}の中身で上書きしようとしたので、保存を止めてディスクの中身に戻しました` +
          '（戻す前の中身は u で出ます）。わざとなら、コマンド「Allow the next overwrite…」の後に保存し直してください。' +
          `記録: ${GUARD_LOG}`,
        0
      );
      return true;
    } catch (err) {
      console.error('dotfiles-vim: the overwrite guard failed; saving anyway', err);
      return false;
    }
  }

  // 新しい中身（空白を除いて after）と同じ別のノート: 今の中身（大きさの近いものだけ読む）、次にファイルの
  // 復元に残る版（Obsidian の内部の口。無い版の Obsidian では見ない）。見つからなければ null
  async sameAsOtherNote(file, data, after) {
    const { vault } = this.app;
    const lo = after.length;
    const hi = Buffer.byteLength(data) * 2 + 64;
    for (const other of vault.getMarkdownFiles()) {
      if (other !== file && other.stat.size >= lo && other.stat.size <= hi && squash(await vault.cachedRead(other)) === after) {
        return { path: other.path, ts: null };
      }
    }
    const db = this.app.internalPlugins?.getPluginById?.('file-recovery')?.instance?.db;
    if (!db) {
      return null;
    }
    let found = null;
    let cursor = await db.transaction('backups', 'readonly').store.openCursor();
    while (cursor) {
      const { path: p, ts, data: d } = cursor.value;
      if (p !== file.path && typeof d === 'string' && d.length >= lo && d.length <= hi && squash(d) === after) {
        // 一番新しい版を出す
        if (!found || ts > found.ts) {
          found = { path: p, ts };
        }
      }
      cursor = await cursor.continue();
    }
    return found;
  }

  // 止めた後、そのファイルを開いているタブをディスクの中身に戻す。配られた中身が残っていると、次の保存で
  // また書こうとするため。Obsidian の外の変更の読み直し（差分で入れるので u で戻せる）を使う。いまは保存の
  // 途中（save の中）なので、それが終わってから
  restoreFromDisk(file) {
    setTimeout(() => {
      for (const leaf of this.app.workspace.getLeavesOfType('markdown')) {
        const { view } = leaf;
        if (view.file !== file || typeof view.loadFileInternal !== 'function') {
          continue;
        }
        view.lastSavedData = null;
        view.dirty = false;
        view.loadFileInternal(file, false).catch((err) => console.error('dotfiles-vim: could not reload', file.path, err));
      }
    }, 0);
  }

  logOverwrite(kind, file, before, data, from, stack) {
    const size = (text) => ({ chars: text.length, lines: text.split(/\r?\n/).length });
    const entry = {
      at: new Date().toISOString(),
      kind,
      path: file.path,
      from,
      before: size(before),
      after: size(data),
      kept: Math.round(keptRatio(before, data) * 100) / 100,
      stack: (stack || '').split('\n').slice(2, 12).map((s) => s.trim()),
      leaves: this.app.workspace.getLeavesOfType('markdown').map((leaf) => {
        const text = leaf.view.editor?.getValue();
        return {
          id: leaf.id,
          file: leaf.view.file?.path,
          active: leaf === this.app.workspace.activeLeaf,
          mode: leaf.view.getMode?.(),
          chars: text?.length,
          holdsNew: text === data,
        };
      }),
      recent: this.recent.slice(),
    };
    try {
      fs.mkdirSync(path.dirname(GUARD_LOG), { recursive: true });
      fs.appendFileSync(GUARD_LOG, JSON.stringify(entry) + '\n');
    } catch (err) {
      console.error('dotfiles-vim: could not write', GUARD_LOG, err);
    }
  }

  off() {
    // ime.exe は前面のウィンドウの IME を切る。他のアプリが前面の時は触らない
    if (!this.ime || !document.hasFocus()) {
      return;
    }
    execFile(this.ime, ['0'], { windowsHide: true }, (err) => {
      if (err) {
        console.warn('dotfiles-vim: ime.exe failed', err);
      }
    });
  }
};
