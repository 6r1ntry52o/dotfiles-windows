// Obsidian の Vim モードを Neovim（LazyVim）に寄せる。dotfiles-windows の nvim と同じ動きを 3 つ足す
// （もう 1 つ、今いる分割のカーソルの行を塗るのは styles.css だけでやる）。
//
//   1. 今のモードをステータスバーの左端に出す（NORMAL・INSERT・VISUAL・V-LINE・V-BLOCK・REPLACE・
//      COMMAND）。色は nvim の lualine（kanagawa wave）と同じ（styles.css）
//   2. INSERT 以外の間は IME を必ず OFF にする（nvim/lua/config/ime.lua の Obsidian 版）。
//      Esc で戻った直後に IME が ON のままだと、h/j/k/l や dd が IME に食われて
//      「ひじくる」のような未確定文字になる＝ノーマルモードのキーが1つも通らない
//   3. ノーマルモードの Ctrl+O / Ctrl+I で、前・次に開いていた所へ戻る・進む（nvim のジャンプリストの
//      代わりに Obsidian のタブの履歴）。それ以外の所では今までどおりクイックスイッチャー・斜体
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
const { EditorView } = require('@codemirror/view');
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
      const cm = this.activeVim();
      if (cm) {
        this.hook(cm);
        const mode = this.modeOf(cm);
        this.modeEl.setText(MODE_LABELS[mode]);
        this.modeEl.dataset.mode = mode;
      }
      this.modeEl.toggle(!!cm);
    });
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
      this.showMode();
    };
    const onDialog = () => this.showMode();
    cm.on('vim-mode-change', onMode);
    cm.on('dialog', onDialog);
    this.hooked.set(cm, { onMode, onDialog });
  }

  unhook(cm) {
    const { onMode, onDialog } = this.hooked.get(cm);
    cm.off('vim-mode-change', onMode);
    cm.off('dialog', onDialog);
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
