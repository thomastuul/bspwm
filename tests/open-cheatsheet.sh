#!/usr/bin/env bash
# Regression checks for the standalone cheatsheet viewer.

set -o errexit -o nounset -o pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
viewer="$repository_root/bin/open-cheatsheet.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p "$fixture/config" "$fixture/sheets" "$fixture/outside"
touch "$fixture/sheets/guide.md"
touch "$fixture/sheets/notes.txt"
touch "$fixture/sheets/manual.PDF"
touch "$fixture/sheets/page.html"
touch "$fixture/sheets/image.png"
touch "$fixture/sheets/unsupported.bin"
touch "$fixture/outside/private.txt"
ln -s "$fixture/outside/private.txt" "$fixture/sheets/escape.txt"

{
    printf 'sheets_dir=%q\n' "$fixture/sheets"
    printf 'terminal=%q\n' /bin/echo
    printf 'md_viewer=%q\n' /bin/true
    printf 'text_viewer=%q\n' /bin/true
    printf 'desktop_opener=%q\n' /bin/true
} >"$fixture/config/cht.conf"

run_viewer() {
    CHEATSHEET_NOTIFY=0 XDG_CONFIG_HOME="$fixture/config" \
        "$viewer" --dry-run "$1"
}

markdown_command=$(run_viewer guide.md)
[[ $markdown_command == /bin/echo\ -e\ /bin/true\ *guide.md* ]]

text_command=$(run_viewer notes.txt)
[[ $text_command == /bin/echo\ -e\ /bin/true\ *notes.txt* ]]

for document in manual.PDF page.html image.png; do
    desktop_command=$(run_viewer "$document")
    [[ $desktop_command == /bin/true\ *"$document"* ]]
done

if run_viewer unsupported.bin >/dev/null 2>&1; then
    printf 'unsupported file type was accepted\n' >&2
    exit 1
fi

if run_viewer escape.txt >/dev/null 2>&1; then
    printf 'symlink outside the cheatsheet directory was accepted\n' >&2
    exit 1
fi

if run_viewer ../outside/private.txt >/dev/null 2>&1; then
    printf 'parent traversal outside the cheatsheet directory was accepted\n' >&2
    exit 1
fi

if run_viewer missing.md >/dev/null 2>&1; then
    printf 'missing cheatsheet was accepted\n' >&2
    exit 1
fi

printf 'open-cheatsheet tests passed\n'
