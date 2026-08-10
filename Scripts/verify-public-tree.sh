#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_PATH="${1:-build/PlansBar.app}"
EXPECTED_BUNDLE_ID="${PLANSBAR_EXPECTED_BUNDLE_ID:-io.github.zergzorg.plansbar}"
failures=0

candidate_files() {
    git ls-files -z --cached --others --exclude-standard
}

contains_literal() {
    local pattern="$1"
    local file
    while IFS= read -r -d '' file; do
        if grep -I -F -q -- "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
    done < <(candidate_files)
    return 1
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    failures=1
}

scan_literal() {
    local label="$1"
    local pattern="$2"
    local file
    local matches

    while IFS= read -r -d '' file; do
        matches="$(grep -a -n -F -- "$pattern" "$file" 2>/dev/null || true)"
        if [[ -n "$matches" ]]; then
            printf 'ERROR: %s in %s\n%s\n' "$label" "$file" "$matches" >&2
            failures=1
        fi
    done < <(candidate_files)

    if [[ -d "$BUNDLE_PATH" ]]; then
        while IFS= read -r -d '' file; do
            matches="$(grep -a -n -F -- "$pattern" "$file" 2>/dev/null || true)"
            if [[ -n "$matches" ]]; then
                printf 'ERROR: %s in bundle file %s\n' "$label" "$file" >&2
                failures=1
            fi
        done < <(find "$BUNDLE_PATH" -type f -print0)
    fi
}

private_terms=(
    'plans-''dashboard'
    'kp-''v3'
    'kp-''v3-main'
    'Codex ''Proxy'
)

users_root='/'Users'/'
private_terms+=("${users_root}ai")

for term in "${private_terms[@]}"; do
    scan_literal "private term" "$term"
done

scan_literal "absolute macOS user path" "$users_root"

if [[ -n "${PLANSBAR_PRIVATE_TERMS_FILE:-}" ]]; then
    if [[ ! -f "$PLANSBAR_PRIVATE_TERMS_FILE" ]]; then
        fail "PLANSBAR_PRIVATE_TERMS_FILE does not exist"
    else
        while IFS= read -r term; do
            [[ -z "$term" || "$term" == \#* ]] && continue
            scan_literal "private term" "$term"
        done < "$PLANSBAR_PRIVATE_TERMS_FILE"
    fi
fi

publishable_cache="$(git ls-files --cached --others --exclude-standard | grep -E '(^|/)(node_modules|dist|coverage|build|\.build|\.DS_Store)(/|$)' || true)"
if [[ -n "$publishable_cache" ]]; then
    printf 'ERROR: publishable cache or build output:\n%s\n' "$publishable_cache" >&2
    failures=1
fi

secret_matches="$(while IFS= read -r -d '' file; do
    grep -I -n -E '(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' "$file" 2>/dev/null || true
done < <(candidate_files))"
if [[ -n "$secret_matches" ]]; then
    printf 'ERROR: possible secret in publishable tree:\n%s\n' "$secret_matches" >&2
    failures=1
fi

if ! contains_literal "$EXPECTED_BUNDLE_ID"; then
    fail "expected bundle identifier is absent from the publishable tree"
fi

if [[ ! -d "$BUNDLE_PATH" ]]; then
    fail "bundle not found at $BUNDLE_PATH"
else
    actual_bundle_id="$(plutil -extract CFBundleIdentifier raw "$BUNDLE_PATH/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$actual_bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
        fail "bundle identifier is '$actual_bundle_id', expected '$EXPECTED_BUNDLE_ID'"
    fi
fi

if git rev-parse --verify HEAD >/dev/null 2>&1; then
    for term in "${private_terms[@]}" "$users_root"; do
        if git log --format= --patch --all | grep -a -F -q -- "$term"; then
            fail "private term is present in Git history"
        fi
    done
fi

if (( failures > 0 )); then
    exit 1
fi

printf 'Public tree audit passed.\n'
