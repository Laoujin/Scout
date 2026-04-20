import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, cpSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

function setupAtlasCopy() {
  const dir = mkdtempSync(join(tmpdir(), 'atlas-'));
  cpSync('tests/fixtures/atlas', dir, { recursive: true });
  return dir;
}

test('regenerates index sorted newest-first', () => {
  const atlas = setupAtlasCopy();
  try {
    execFileSync('node', ['scripts/build_index.js', atlas], { stdio: 'pipe' });
    const html = readFileSync(join(atlas, 'index.html'), 'utf8');

    const iGamma = html.indexOf('Gamma deep dive');
    const iBeta = html.indexOf('Beta overview');
    const iAlpha = html.indexOf('Alpha research');
    assert.ok(iGamma >= 0 && iBeta >= 0 && iAlpha >= 0, 'all three entries present');
    assert.ok(iGamma < iBeta, 'gamma before beta');
    assert.ok(iBeta < iAlpha, 'beta before alpha');
  } finally {
    rmSync(atlas, { recursive: true, force: true });
  }
});

test('each entry links to its folder', () => {
  const atlas = setupAtlasCopy();
  try {
    execFileSync('node', ['scripts/build_index.js', atlas], { stdio: 'pipe' });
    const html = readFileSync(join(atlas, 'index.html'), 'utf8');
    assert.match(html, /href="research\/2026-03-01-gamma\/"/);
    assert.match(html, /href="research\/2026-02-14-beta\/"/);
    assert.match(html, /href="research\/2026-01-05-alpha\/"/);
  } finally {
    rmSync(atlas, { recursive: true, force: true });
  }
});

test('includes depth badge and tags', () => {
  const atlas = setupAtlasCopy();
  try {
    execFileSync('node', ['scripts/build_index.js', atlas], { stdio: 'pipe' });
    const html = readFileSync(join(atlas, 'index.html'), 'utf8');
    assert.match(html, /depth-badge[^>]*>ceo</);
    assert.match(html, /depth-badge[^>]*>standard</);
    assert.match(html, /depth-badge[^>]*>deep</);
    assert.match(html, /class="tag"[^>]*>software</);
    assert.match(html, /class="tag"[^>]*>hardware</);
  } finally {
    rmSync(atlas, { recursive: true, force: true });
  }
});

test('does not leak raw scout-meta script into index', () => {
  const atlas = setupAtlasCopy();
  try {
    execFileSync('node', ['scripts/build_index.js', atlas], { stdio: 'pipe' });
    const html = readFileSync(join(atlas, 'index.html'), 'utf8');
    assert.doesNotMatch(html, /<script type="application\/json"/);
  } finally {
    rmSync(atlas, { recursive: true, force: true });
  }
});

test('card shows topic, format, citations, reading time, depth accent', () => {
  const atlas = setupAtlasCopy();
  try {
    execFileSync('node', ['scripts/build_index.js', atlas], { stdio: 'pipe' });
    const html = readFileSync(join(atlas, 'index.html'), 'utf8');

    // topics from each fixture
    assert.match(html, /entry-prompt[^>]*>Compare X vs Y</);
    assert.match(html, /entry-prompt[^>]*>Beta tools landscape</);
    assert.match(html, /entry-prompt[^>]*>Gamma</);

    // format badges
    assert.match(html, /class="format-badge"[^>]*>html</);
    assert.match(html, /class="format-badge"[^>]*>md</);

    // citation counts
    assert.match(html, /18 sources/);
    assert.match(html, /6 sources/);
    assert.match(html, /42 sources/);

    // reading times
    assert.match(html, /~3 min/);
    assert.match(html, /~1 min/);
    assert.match(html, /~8 min/);

    // depth data attributes drive the CSS accent
    assert.match(html, /data-depth="ceo"/);
    assert.match(html, /data-depth="standard"/);
    assert.match(html, /data-depth="deep"/);
  } finally {
    rmSync(atlas, { recursive: true, force: true });
  }
});
