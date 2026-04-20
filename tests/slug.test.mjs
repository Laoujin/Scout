import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

function slugify(input) {
  return execFileSync(
    'bash',
    ['-c', 'source scripts/slug.sh; slugify "$1"', 'slug-test', input],
    { encoding: 'utf8' }
  );
}

const cases = [
  ['NAS Replacement',         'nas-replacement'],
  ['Restaurants in Ghent!?',  'restaurants-in-ghent'],
  ['AI —— driven   development', 'ai-driven-development'],
  ['Café résumé naïve',       'cafe-resume-naive'],
  ['',                        ''],
];

for (const [input, expected] of cases) {
  test(`slugify ${JSON.stringify(input)}`, () => {
    assert.equal(slugify(input), expected);
  });
}

test('truncates to 50 chars, no trailing dash', () => {
  const s = slugify('This is a very long topic title that will surely exceed fifty characters in total');
  assert.ok(s.length <= 50, `length was ${s.length}`);
  assert.notEqual(s.slice(-1), '-');
});
