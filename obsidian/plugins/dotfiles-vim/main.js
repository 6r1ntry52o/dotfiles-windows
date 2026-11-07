// Obsidian の Vim モードを Neovim（LazyVim）に寄せる。dotfiles-windows の nvim と同じ動きを 4 つ足す
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

const { MarkdownView, Plugin } = require('obsidian');
const { Compartment } = require('@codemirror/state');
const { EditorView, lineNumbers } = require('@codemirror/view');
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

    this.registerDomEvent(document, 'focusin', (ev) => {
      this.offUnlessInsert(ev.target);
      this.showMode();
    });
    this.registerDomEvent(window, 'focus', () => this.offUnlessInsert(document.activeElement));
    this.registerEvent(this.app.workspace.on('file-open', () => this.offUnlessInsert(document.activeElement)));
    this.registerEvent(this.app.workspace.on('active-leaf-change', () => this.showMode()));
    this.registerEvent(this.app.workspace.on('layout-change', () => this.showMode()));
    this.app.workspace.onLayoutReady(() => {
      this.offUnlessInsert(document.activeElement);
      this.showMode();
    });
  }

  onunload() {
    cancelAnimationFrame(this.frame);
    for (const cm of this.hooked.keys()) {
      this.unhook(cm);
    }
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
    // INSERT 中の status には打った文字もたまっていくので、ノーマルとビジュアルの時だけ出す
    let keys = '';
    if (cm) {
      this.hook(cm);
      const mode = this.modeOf(cm);
      this.modeEl.setText(MODE_LABELS[mode]);
      this.modeEl.dataset.mode = mode;
      this.markMode(cm, mode);
      if (mode === 'normal' || mode.startsWith('visual')) {
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

  // ノーマルモードの編集画面にフォーカスがある時だけ inNormal、それ以外はこのキーの元の動き
  runByMode(inNormal, otherwise) {
    const cm = this.vimOf(document.activeElement);
    const normal = cm && !cm.state.vim.insertMode && !cm.state.vim.visualMode;
    this.app.commands.executeCommandById(normal ? inNormal : otherwise);
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
