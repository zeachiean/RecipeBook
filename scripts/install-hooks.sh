#!/usr/bin/env bash
# Install git hooks for RecipeBook.
# Safe to re-run — overwrites previous hooks.
#
# What this installs:
#   pre-commit : runs `lua tests/run.lua` and blocks the commit on failure
#   pre-push   : runs tests + lints CHANGELOG tag format on tag pushes
#
# Hooks are NOT committed (git hooks live in .git/hooks/, which isn't tracked).
# Every clone has to run this script once. Matches the shared CLAUDE.md rule
# "Run tests before and after making changes" — turns the rule into a gate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "error: not a git repository at $REPO_ROOT"
    exit 1
fi

mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# pre-commit: run addon tests; block commit on failure.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -d tests ]; then
    exit 0
fi

if ! command -v lua >/dev/null 2>&1; then
    echo "[pre-commit] WARNING: lua not installed, skipping tests"
    exit 0
fi

echo "[pre-commit] Running lua tests/run.lua ..."
if ! lua tests/run.lua; then
    echo "[pre-commit] Tests FAILED — commit blocked."
    echo "[pre-commit] Fix the tests or commit with --no-verify (use sparingly)."
    exit 1
fi
echo "[pre-commit] Tests passed."
HOOK

cat > "$HOOKS_DIR/pre-push" <<'HOOK'
#!/usr/bin/env bash
# pre-push: run tests again (belt-and-suspenders), validate tag format on tag pushes.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Read refs being pushed from stdin
while read -r local_ref local_sha remote_ref remote_sha; do
    # Tag pushes: validate v-prefix format
    if [[ "$local_ref" == refs/tags/* ]]; then
        tag="${local_ref#refs/tags/}"
        if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
            echo "[pre-push] Tag '$tag' does not match required format vMAJOR.MINOR.PATCH[-qualifier]"
            echo "[pre-push] Example: v3.7.2 or v3.7.2-rc.1"
            echo "[pre-push] Push blocked."
            exit 1
        fi
    fi
done

if [ -d tests ] && command -v lua >/dev/null 2>&1; then
    echo "[pre-push] Running lua tests/run.lua ..."
    if ! lua tests/run.lua; then
        echo "[pre-push] Tests FAILED — push blocked."
        exit 1
    fi
    echo "[pre-push] Tests passed."
fi
HOOK

chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push"

echo "Installed hooks in $HOOKS_DIR:"
echo "  pre-commit : runs tests before each commit"
echo "  pre-push   : runs tests + validates tag format before each push"
echo ""
echo "To bypass (rare): git commit --no-verify  /  git push --no-verify"
