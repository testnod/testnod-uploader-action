#!/usr/bin/env bash
# Runs ShellCheck on every `run:` block in action.yml. actionlint only checks
# scripts in workflow files, not the steps of a composite action.
# Requires yq (preinstalled on GitHub's Ubuntu runners) and shellcheck.
#
# Excluded checks:
#   SC2153  "possible misspelling": step variables come from each step's `env:`
#           block, which ShellCheck can't see
#   SC2129  "group redirects to the same file": a style preference for the
#           separate `>> "$GITHUB_OUTPUT"` lines
set -euo pipefail

ACTION_FILE="${1:-action.yml}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STEP_COUNT=$(yq '.runs.steps | length' "$ACTION_FILE")
STATUS=0

for ((i = 0; i < STEP_COUNT; i++)); do
  RUN=$(yq ".runs.steps[$i].run // \"\"" "$ACTION_FILE")
  if [ -z "$RUN" ]; then
    continue
  fi

  NAME=$(yq ".runs.steps[$i].name" "$ACTION_FILE")
  SCRIPT="${TMP_DIR}/step-${i}.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$RUN" > "$SCRIPT"

  echo "Checking step: ${NAME}"
  if ! shellcheck --exclude=SC2153,SC2129 "$SCRIPT"; then
    echo "::error file=${ACTION_FILE}::ShellCheck failed for step '${NAME}' (line numbers are relative to the step's run block, plus 1)"
    STATUS=1
  fi
done

exit "$STATUS"
