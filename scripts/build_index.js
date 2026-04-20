#!/usr/bin/env node
// Regenerate atlas/index.html by scanning atlas/research/*/index.{html,md} metadata.
// Usage: node scripts/build_index.js <atlas-root>

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const atlasRoot = process.argv[2];
if (!atlasRoot) {
  console.error('Usage: build_index.js <atlas-root>');
  process.exit(1);
}

const researchDir = join(atlasRoot, 'research');

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function parseHtmlMeta(content) {
  const m = content.match(/<script[^>]*id=["']scout-meta["'][^>]*>([\s\S]*?)<\/script>/);
  if (!m) return null;
  try { return JSON.parse(m[1].trim()); } catch { return null; }
}

function parseMdFrontmatter(content) {
  const m = content.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const obj = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^(\w+):\s*(.*)$/);
    if (!kv) continue;
    let v = kv[2].trim();
    if (v.startsWith('[') && v.endsWith(']')) {
      v = v.slice(1, -1).split(',').map(x => x.trim().replace(/^['"]|['"]$/g, '')).filter(Boolean);
    } else {
      v = v.replace(/^['"]|['"]$/g, '');
    }
    obj[kv[1]] = v;
  }
  return obj;
}

function loadEntries() {
  let folders = [];
  try { folders = readdirSync(researchDir); } catch { return []; }
  const entries = [];
  for (const folder of folders) {
    const full = join(researchDir, folder);
    if (!statSync(full).isDirectory()) continue;
    const candidates = [join(full, 'index.html'), join(full, 'index.md')];
    for (const file of candidates) {
      let content;
      try { content = readFileSync(file, 'utf8'); } catch { continue; }
      const meta = file.endsWith('.html') ? parseHtmlMeta(content) : parseMdFrontmatter(content);
      if (!meta || !meta.date) continue;
      entries.push({ ...meta, folder });
      break;
    }
  }
  entries.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
  return entries;
}

function renderEntry(e) {
  const tags = Array.isArray(e.tags) ? e.tags : [];
  const tagHtml = tags.map(t => `<span class="tag">${escapeHtml(t)}</span>`).join(' ');
  return `
    <article class="entry">
      <h2><a href="research/${escapeHtml(e.folder)}/">${escapeHtml(e.title)}</a></h2>
      <p>${escapeHtml(e.summary || '')}</p>
      <p class="meta">
        <span class="depth-badge">${escapeHtml(e.depth || 'standard')}</span>
        <time>${escapeHtml(e.date)}</time>
        ${tagHtml}
      </p>
    </article>`;
}

function render(entries) {
  const body = entries.length === 0
    ? '<p><em>No research published yet.</em></p>'
    : entries.map(renderEntry).join('\n');
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Atlas</title>
  <link rel="stylesheet" href="assets/base.css">
</head>
<body>
  <header><h1>Atlas</h1><p>Research findings. Newest first.</p></header>
  <main>
${body}
  </main>
</body>
</html>
`;
}

const entries = loadEntries();
writeFileSync(join(atlasRoot, 'index.html'), render(entries));
console.log(`Wrote index with ${entries.length} entries.`);
