#!/usr/bin/env bash
#
# Golden-file template tests: render the chart for a set of value profiles
# and compare the output against the committed golden files.
#
#   tests/golden-test.sh           compare (CI mode, non-zero exit on diff)
#   tests/golden-test.sh --update  regenerate the golden files, then review
#                                  the git diff — it shows exactly what your
#                                  chart change does to the rendered output
#
# Determinism: all generated passwords are pinned via fixed-secrets.yaml and
# helm template never reaches a cluster, so `lookup` is always empty. The
# release is deliberately named "golden" so hardcoded "wger-..." resource
# names show up as diffs (only the wger-pg-init ConfigMap is allowed to be
# static, see configmap-postgres.yaml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/wger"
GOLDEN="$ROOT/tests/golden"
UPDATE="${1:-}"

# subchart dependencies, pinned via Chart.lock
if [ ! -e "$CHART"/charts/postgres-*.tgz ] || [ ! -e "$CHART"/charts/redis-*.tgz ]; then
  helm dependency build "$CHART"
fi

declare -A PROFILES=(
  [default]=""
  [full]="-f $GOLDEN/profiles/full.yaml"
  [external-db]="-f $GOLDEN/profiles/external-db.yaml"
  [prod-example]="-f $ROOT/example/prod_values.yaml"
)

rc=0
for p in default full external-db prod-example; do
  out="$(mktemp)"
  # shellcheck disable=SC2086  # PROFILES entries are intentionally word-split
  helm template golden "$CHART" --namespace golden-ns \
    -f "$GOLDEN/fixed-secrets.yaml" ${PROFILES[$p]} > "$out"
  if [ "$UPDATE" = "--update" ]; then
    cp "$out" "$GOLDEN/$p.yaml"
    echo "updated: $p"
  elif diff -u "$GOLDEN/$p.yaml" "$out"; then
    echo "ok: $p"
  else
    echo "FAIL: profile '$p' renders differently than its golden file (see diff above)."
    echo "      If the change is intentional: tests/golden-test.sh --update && git diff tests/golden/"
    rc=1
  fi
  rm -f "$out"
done
exit $rc
