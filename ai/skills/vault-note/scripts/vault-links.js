// Runs inside Obsidian (obsidian eval), called by vault-links.ps1. Do not run it with node.
// vault-links.ps1 replaces `__REQ__` with the request, base64 of UTF-8 JSON
// ({ note, context, limit, direction }), and sends this whole file base64-encoded too, so no
// quote, backslash or newline has to survive the command line.
// It answers from Obsidian's own link index (metadataCache), so links resolve exactly as in the
// app: by name, alias, heading or block, wherever the note lives.
(async () => {
  const bytes = Uint8Array.from(atob('__REQ__'), (c) => c.charCodeAt(0));
  const req = JSON.parse(new TextDecoder().decode(bytes));
  const mc = app.metadataCache;
  const MAX_CHARS = 300;

  const clip = (s) => (s.length > MAX_CHARS ? s.slice(0, MAX_CHARS) + '…' : s);

  // note: a vault path ("note/a.md"), a path without .md, or a name as in [[name]].
  function findFile(q) {
    const s = String(q).replace(/\\/g, '/').replace(/^\.?\//, '');
    const root = app.vault.adapter.basePath.replace(/\\/g, '/').replace(/\/$/, '');
    const rel = s.toLowerCase().startsWith(root.toLowerCase() + '/') ? s.slice(root.length + 1) : s;
    return app.vault.getFileByPath(rel)
      || app.vault.getFileByPath(rel + '.md')
      || mc.getFirstLinkpathDest(rel.replace(/\.md$/i, ''), '');
  }

  const linesOf = new Map();
  async function lines(file) {
    if (!linesOf.has(file.path)) linesOf.set(file.path, (await app.vault.cachedRead(file)).split(/\r?\n/));
    return linesOf.get(file.path);
  }
  // Lines around a 0-based line, keyed by their 1-based number.
  async function around(file, line) {
    const all = await lines(file);
    const out = {};
    for (let i = Math.max(0, line - req.context); i <= Math.min(all.length - 1, line + req.context); i++) {
      out[i + 1] = clip(all[i]);
    }
    return out;
  }

  // Every link of a note with its 0-based line (null for frontmatter) and resolved file.
  function refsOf(file) {
    const c = mc.getFileCache(file) || {};
    const refs = [];
    for (const l of c.links || []) refs.push({ l, kind: 'link', line: l.position.start.line });
    for (const l of c.embeds || []) refs.push({ l, kind: 'embed', line: l.position.start.line });
    for (const l of c.frontmatterLinks || []) refs.push({ l, kind: 'frontmatter', line: null, key: l.key });
    for (const r of refs) {
      r.dest = mc.getFirstLinkpathDest(r.l.link.split('#')[0].split('|')[0], file.path);
      if (!r.l.link.split('#')[0]) r.dest = file; // [[#heading]] points into the note itself
    }
    return refs.sort((a, b) => (a.line ?? -1) - (b.line ?? -1));
  }

  // One entry per line: several links on a line share its context.
  async function group(file, refs, describe) {
    const byLine = new Map();
    for (const r of refs) {
      const k = r.line === null ? 'fm:' + r.key : r.line;
      if (!byLine.has(k)) byLine.set(k, { r, items: [] });
      byLine.get(k).items.push(describe(r));
    }
    const out = [];
    for (const { r, items } of byLine.values()) {
      const e = r.line === null ? { frontmatter: r.key } : { line: r.line + 1, context: await around(file, r.line) };
      const named = [...new Set(items.filter(Boolean))];
      if (named.length) e.links = named;
      out.push(e);
    }
    return out;
  }

  const file = findFile(req.note);
  if (!file) return JSON.stringify({ error: 'note not found: ' + req.note });

  const result = { vault: app.vault.getName(), note: file.path };
  const describe = (r) => {
    const sub = r.l.link.includes('#') ? '#' + r.l.link.split('#').slice(1).join('#') : '';
    const kind = r.kind === 'embed' ? '!' : '';
    return r.dest ? kind + r.dest.path + sub : kind + r.l.link + ' (unresolved)';
  };

  if (req.direction !== 'in') {
    result.links = await group(file, refsOf(file), describe);
  }

  if (req.direction !== 'out') {
    const sources = Object.entries(mc.resolvedLinks)
      .filter(([src, dests]) => src !== file.path && dests[file.path])
      .map(([src]) => src)
      .sort();
    const backlinks = [];
    let total = 0;
    for (const src of sources) {
      const f = app.vault.getFileByPath(src);
      if (!f) continue;
      const refs = refsOf(f).filter((r) => r.dest && r.dest.path === file.path);
      // The target is the note itself; only a heading or block it points at is worth naming.
      const subpath = (r) => (r.l.link.includes('#') ? '#' + r.l.link.split('#').slice(1).join('#') : '');
      for (const e of await group(f, refs, subpath)) {
        total++;
        if (backlinks.length < req.limit) backlinks.push(Object.assign({ from: src }, e));
      }
    }
    result.backlinks = backlinks;
    if (total > backlinks.length) result.backlinks_omitted = total - backlinks.length;
  }

  return JSON.stringify(result);
})()
