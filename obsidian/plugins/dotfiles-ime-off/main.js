// Obsidian の Vim モードで、INSERT 以外の間は IME を必ず OFF にする（nvim/lua/config/ime.lua の Obsidian 版）。
// Esc で戻った直後に IME が ON のままだと、h/j/k/l や dd が IME に食われて
// 「ひじくる」のような未確定文字になる＝ノーマルモードのキーが1つも通らない。
//
// 正本: dotfiles-windows/obsidian/plugins/dotfiles-ime-off。install.ps1 の 8c が
// <vault>/.obsidian/plugins/dotfiles-ime-off/ に写し、隣に tools/bin/ime.exe も置く
// （写しは上書きするので、直すのはリポの方）。ime.exe は前面のウィンドウ（＝Obsidian）の IME を
// 外から OFF にする（tools/ime/Ime.cs）。ime.exe が無い PC（Sync でプラグインだけ届いた）では何もしない。
//
// 切る時（nvim と同じ）:
//   INSERT（置換を含む）を抜けた時 … InsertLeave
//   編集画面にフォーカスが入った時 … CmdlineLeave（/ や : の入力欄から戻った）と、別のペインや
//                                    サイドバーから入った時
//   Obsidian に戻ってきた時       … FocusGained
//   ノートを開いた時・有効にした時 … VimEnter
// INSERT 中の編集画面は触らない（日本語を打っている最中）。INSERT に入っても ON には戻さない
// ので、日本語を打つ時は F14 を押す。
'use strict';

const { Plugin } = require('obsidian');
const { EditorView } = require('@codemirror/view');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

module.exports = class ImeOffPlugin extends Plugin {
  onload() {
    this.ime = path.join(this.app.vault.adapter.getBasePath(), this.manifest.dir, 'ime.exe');
    if (!fs.existsSync(this.ime)) {
      console.warn(`dotfiles-ime-off: ${this.ime} が無いので何もしない（dotfiles の install.ps1 を流すと入る）`);
      return;
    }
    // Vim の口（編集画面ごと）→ vim-mode-change に付けたハンドラ。外す時に使う
    this.hooked = new Map();

    this.registerDomEvent(document, 'focusin', (ev) => this.offUnlessInsert(ev.target));
    this.registerDomEvent(window, 'focus', () => this.offUnlessInsert(document.activeElement));
    this.registerEvent(this.app.workspace.on('file-open', () => this.offUnlessInsert(document.activeElement)));
    this.app.workspace.onLayoutReady(() => this.offUnlessInsert(document.activeElement));
  }

  onunload() {
    for (const [cm, handler] of this.hooked ?? []) {
      cm.off('vim-mode-change', handler);
    }
  }

  // el が編集画面の本文なら、その Vim の口（CodeMirror 5 互換・state.vim を持つ）。
  // 本文でない（/ の入力欄・サイドバー）・Vim モードでない時は undefined
  vimOf(el) {
    const content = el instanceof Element ? el.closest('.cm-content') : null;
    const view = content ? EditorView.findFromDOM(content.closest('.cm-editor')) : null;
    const cm = view?.cm;
    return cm?.state?.vim ? cm : undefined;
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

  // INSERT を抜けた時に切る。ノーマルとビジュアルの行き来では呼ばない（ime.exe を起こさない）
  hook(cm) {
    if (this.hooked.has(cm)) {
      return;
    }
    let mode = cm.state.vim.insertMode ? 'insert' : 'normal';
    const handler = (ev) => {
      const wasInsert = mode === 'insert' || mode === 'replace';
      mode = ev?.mode ?? mode;
      if (wasInsert && mode !== 'insert' && mode !== 'replace') {
        this.off();
      }
    };
    cm.on('vim-mode-change', handler);
    this.hooked.set(cm, handler);
  }

  off() {
    // ime.exe は前面のウィンドウの IME を切る。他のアプリが前面の時は触らない
    if (!document.hasFocus()) {
      return;
    }
    execFile(this.ime, ['0'], { windowsHide: true }, (err) => {
      if (err) {
        console.warn('dotfiles-ime-off: ime.exe failed', err);
      }
    });
  }
};
