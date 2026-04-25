#!/usr/bin/env bash
# Audit H7: pre-recording checklist. Runs in <60 seconds and preempts
# the three Saturday-audit failure modes (sentence-transformers cache
# cold start, Ollama daemon unreachable, classifier pickle silent
# fallback) plus a smoke-test for the canonical adapter path Tim will
# demo against.
#
# Run once before each take. Exits 0 if all green, non-zero if any
# check fails (the failure surfaces at the bottom so it's the last
# thing on screen — no scrolling needed during recording).

set -uo pipefail
LC_ALL=C

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd -P)"

PASS=0
FAIL=0
SKIP=0

emit() {
  local status="$1"; local label="$2"; local detail="${3:-}"
  case "$status" in
    PASS) printf "  [\033[0;32mPASS\033[0m] %s %s\n" "$label" "$detail"; PASS=$((PASS + 1)) ;;
    FAIL) printf "  [\033[0;31mFAIL\033[0m] %s %s\n" "$label" "$detail"; FAIL=$((FAIL + 1)) ;;
    SKIP) printf "  [skip] %s %s\n" "$label" "$detail"; SKIP=$((SKIP + 1)) ;;
  esac
}

echo "Pre-record checklist (Kiln demo)"
echo "================================"

# ---- 1. ANTHROPIC_API_KEY for cloud features --------------------------------

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  emit PASS "1. ANTHROPIC_API_KEY"  "(set, ${#ANTHROPIC_API_KEY} chars)"
else
  emit SKIP "1. ANTHROPIC_API_KEY"  "(not set — Voice Coach / Deep Curation cloud paths will surface 'API key missing')"
fi

# ---- 2. Sentence-transformers HF cache --------------------------------------

ST_PROBE_RC=0
PROBE_OUT="$(uv --project packages/kiln_trainer run --group dev python -c "
from sentence_transformers import SentenceTransformer
m = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
v = m.encode(['warmup'], show_progress_bar=False)
print(f'ok dim={len(v[0])}')
" 2>&1)" || ST_PROBE_RC=$?

if [ "$ST_PROBE_RC" -eq 0 ] && echo "$PROBE_OUT" | grep -q "ok dim="; then
  emit PASS "2. sentence-transformers cache"  "($(echo "$PROBE_OUT" | grep -o 'dim=[0-9]*'))"
else
  emit FAIL "2. sentence-transformers cache"  "(uv run failed; first call to embed-search will stall ~30s)"
fi

# ---- 3. Ollama daemon -------------------------------------------------------

if command -v ollama >/dev/null 2>&1; then
  if ollama list >/dev/null 2>&1; then
    n="$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
    emit PASS "3. Ollama daemon"  "($n model(s) loaded)"
  else
    emit FAIL "3. Ollama daemon"  "(installed but not running — run 'ollama serve')"
  fi
else
  emit FAIL "3. Ollama"           "(not on PATH — install or run with non-Ollama features only)"
fi

# ---- 4. Quality classifier smoke -------------------------------------------

ARTIFACT="$REPO_ROOT/packages/kiln_trainer/artifacts/quality-classifier.pkl"
if [ -f "$ARTIFACT" ]; then
  CLASS_RC=0
  # The classify subcommand exposes ``--text`` for single-text input
  # which avoids the temp-file dance.
  CLASS_OUT="$(uv --project packages/kiln_trainer run --group dev python -m kiln_trainer classify \
    --mode quality --artifact "$ARTIFACT" \
    --text "I broke a pot Sunday and the dog watched." 2>&1)" || CLASS_RC=$?
  if [ "$CLASS_RC" -eq 0 ] && echo "$CLASS_OUT" | grep -q '"event":"classification"'; then
    emit PASS "4. classify subcommand"  "(produced a classification event)"
  else
    emit FAIL "4. classify subcommand"  "(rc=$CLASS_RC; gate may silently no-op at demo time)"
  fi
else
  emit FAIL "4. classify pickle"   "($ARTIFACT not found)"
fi

# ---- 5. Distilled manifests + ship-bar status -------------------------------

MANIFESTS_OK=true
for COMPONENT in quality-classifier preference-judge style-extractor; do
  M="$REPO_ROOT/distilled/$COMPONENT/manifest.json"
  if [ ! -f "$M" ]; then
    MANIFESTS_OK=false
    break
  fi
done

if [ "$MANIFESTS_OK" = true ]; then
  emit PASS "5. distilled manifests" "(3 components × manifest.json present)"
else
  emit FAIL "5. distilled manifests" "(re-run scripts/build_distilled_manifests.py)"
fi

# ---- 6. Demo-check ----------------------------------------------------------

DEMO_OUT="$(python3 scripts/demo-check.py 2>&1 | tail -3)"
if echo "$DEMO_OUT" | grep -qE "FAIL: 0"; then
  PASS_N="$(echo "$DEMO_OUT" | grep -oE 'PASS: [0-9]+' | grep -oE '[0-9]+')"
  emit PASS "6. make demo-check"     "(PASS: $PASS_N, no failures)"
else
  emit FAIL "6. make demo-check"     "(FAILs present — re-run 'python3 scripts/demo-check.py' for detail)"
fi

# ---- Summary ---------------------------------------------------------------

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "  PASS=$PASS  SKIP=$SKIP  FAIL=$FAIL  ✓ ready to record"
  exit 0
else
  echo "  PASS=$PASS  SKIP=$SKIP  FAIL=$FAIL  ✗ fix failures before recording"
  exit 1
fi
