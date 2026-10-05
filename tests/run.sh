#!/bin/sh
# Everything, stopping at the first failure: syntax, lint, the Lua tests (in both
# tooltip modes), the personal-data guard, the pre-push hook, the package-shape test
# and the release-workflow checks. (The sim is a separate website with its own tests;
# the Lua tests here also write the sample exports it uses.)
set -e
cd "$(dirname "$0")"
SX_DIR="$(cd .. && pwd)/"
export SX_DIR
echo "tools: $(lua5.1 -v 2>&1 | head -1); $(luacheck --version | head -1); $(python3 --version 2>&1); packager $(sha256sum /usr/local/bin/release.sh 2>/dev/null | cut -c1-12 || echo missing)"
rm -f sample_hunter.txt sample_sets.txt cross_samples.txt cross_corpus.txt cross_classes.txt
for f in ../*.lua; do luac5.1 -p "$f"; done
luacheck --config .luacheckrc -q ../*.lua
luacheck -q --std lua51 --no-max-line-length --allow-defined-top --no-global harness.lua tests*.lua
# Lua suite twice: the hidden-tooltip path (what Classic clients use) and the
# C_TooltipInfo path. The static and cross tests don't read tooltips per mode.
for t in tests*.lua; do lua5.1 "$t"; done
for t in tests.lua tests_sets.lua tests_audit*.lua; do
  printf '[C_TooltipInfo] '
  SX_TIPMODE=api lua5.1 "$t"
done
python3 guard_personal.py
# Every commit, tag and ref, once this is a git repository (CI always is).
if git rev-parse --git-dir >/dev/null 2>&1; then python3 guard_personal.py --history
elif [ "$GITHUB_ACTIONS" = true ]; then echo "FAIL personal-data guard: running on CI, but the checkout has no git history to check"; exit 1
else echo "personal-data guard: not a git repository yet, so there is no history to check"; fi
sh prepush_test.sh
sh package_test.sh
python3 release_check_test.py
echo "All SimBench tests passed."
