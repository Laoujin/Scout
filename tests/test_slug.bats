#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$SCRIPT_DIR/scripts/slug.sh"
}

@test "lowercase conversion" {
  result="$(slugify 'NAS Replacement')"
  [ "$result" = "nas-replacement" ]
}

@test "strips punctuation" {
  result="$(slugify 'Restaurants in Ghent!?')"
  [ "$result" = "restaurants-in-ghent" ]
}

@test "collapses multiple separators" {
  result="$(slugify 'AI —— driven   development')"
  [ "$result" = "ai-driven-development" ]
}

@test "truncates to 50 chars with no trailing dash" {
  long="$(slugify 'This is a very long topic title that will surely exceed fifty characters in total')"
  [ "${#long}" -le 50 ]
  [ "${long: -1}" != "-" ]
}

@test "handles diacritics" {
  result="$(slugify 'Café résumé naïve')"
  [ "$result" = "cafe-resume-naive" ]
}

@test "empty input returns empty" {
  result="$(slugify '')"
  [ "$result" = "" ]
}
