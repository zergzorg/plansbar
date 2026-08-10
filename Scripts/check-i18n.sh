#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

locales=(ru zh-CN es pt-BR ja ko fr de)
version="$(tr -d '\n' < Docs/i18n/VERSION)"
failures=0

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    failures=1
}

actual_locales="$(find Docs/i18n -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')"
expected_locales="$(printf '%s\n' "${locales[@]}" | sort | tr '\n' ' ')"
[[ "$actual_locales" == "$expected_locales" ]] || fail "locale directory set does not match: ${expected_locales}"

readmes=(README.md)
for locale in "${locales[@]}"; do
    file="Docs/i18n/${locale}/README.md"
    [[ -f "$file" ]] || { fail "missing ${file}"; continue; }
    readmes+=("$file")
    grep -F -q 'English is authoritative' "$file" || fail "missing authority marker in ${file}"
    grep -F -q "Source docs version: ${version}" "$file" || fail "wrong source version in ${file}"
    for token in 'Plan-Version: 1' 'docs/plans/{backlog,active,completed}' 'Scripts/build-app.sh' 'plansbar validate-repository'; do
        grep -F -q "$token" "$file" || fail "missing canonical token '${token}' in ${file}"
    done
done

labels=('English' 'Русский' '简体中文' 'Español' 'Português do Brasil' '日本語' '한국어' 'Français' 'Deutsch')
for file in "${readmes[@]}"; do
    for label in "${labels[@]}"; do
        grep -F -q "$label" "$file" || fail "missing language '${label}' in ${file}"
    done
    while IFS= read -r link; do
        [[ "$link" == http* || "$link" == \#* ]] && continue
        target="$(dirname "$file")/$link"
        [[ -e "$target" ]] || fail "broken link '${link}' in ${file}"
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\((.*)\)$/\1/' | sed 's/#.*$//')
done

(( failures == 0 )) || exit 1
printf 'i18n check passed.\n'
