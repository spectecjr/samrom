#!/bin/bash
#
# check.sh -- prove that the annotated source assembles to the same ROM image as the original.
#
# Builds samrom.asm from the repository root and from annotated/, and compares the two binaries byte for byte.
# romtest.asm is not reachable from samrom.asm, so it is built and compared separately. Finally the static
# equivalence checker is run, which reports *which line* differs when something does.
#
# Usage:  annotated/check.sh [options]
#
#   --overlay      copy annotated/*.asm over a copy of the originals and build that, instead of building
#                  annotated/ directly. Equivalent while every file is converted; useful if you are working on a
#                  partial conversion, where the annotated directory does not stand alone.
#   --no-verify    skip verify_annotated.py (the binary comparison alone is the authoritative check)
#   --keep         leave the build directory in place and print its path
#
# Exit status is 0 only if every comparison matched.

set -u

overlay=0
verify=1
keep=0

for arg in "$@"; do
    case "$arg" in
        --overlay)   overlay=1 ;;
        --no-verify) verify=0 ;;
        --keep)      keep=1 ;;
        -h|--help)   sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "check.sh: unknown option '$arg'" >&2; exit 2 ;;
    esac
done

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

# ---------------------------------------------------------------------------------------------------------------------
# Locate pyz80. The pip package installs a console script called "pyz80" (not "pyz80.py", which is what the
# repository's Makefile and make.bat still invoke). On Windows it lands in the per-user scripts directory, which is
# often not on PATH.
# ---------------------------------------------------------------------------------------------------------------------

if ! command -v pyz80 >/dev/null 2>&1; then
    for finder in "sysconfig.get_path('scripts','nt_user')" "sysconfig.get_path('scripts')"; do
        dir=$(python -c "import sysconfig;print($finder)" 2>/dev/null) || continue
        # python may report a Windows path; make it usable from this shell.
        case "$dir" in
            [A-Za-z]:\\*) dir="/$(echo "${dir:0:1}" | tr 'A-Z' 'a-z')/$(echo "${dir:3}" | tr '\\' '/')" ;;
        esac
        if [ -x "$dir/pyz80" ] || [ -f "$dir/pyz80" ]; then
            PATH="$PATH:$dir"
            export PATH
            break
        fi
    done
fi

if ! command -v pyz80 >/dev/null 2>&1; then
    echo "check.sh: pyz80 not found. Install it with:  python -m pip install pyz80" >&2
    exit 2
fi

# ---------------------------------------------------------------------------------------------------------------------

work=$(mktemp -d) || exit 2
if [ "$keep" -eq 0 ]; then
    trap 'rm -rf "$work"' EXIT
fi

status=0

# build <source-dir> <top-level-asm> <output-binary> <label>
build() {
    local dir=$1 src=$2 out=$3 label=$4
    local log="$work/$(basename "$out").log"
    if ( cd "$dir" && pyz80 --obj="$out" -o "$work/$(basename "$out").dsk" "$src" ) >"$log" 2>&1; then
        return 0
    fi
    echo "*** $label BUILD FAILED ***"
    tail -30 "$log"
    return 1
}

# compare <original-binary> <annotated-binary> <label>
compare() {
    local a=$1 b=$2 label=$3
    if cmp -s "$a" "$b"; then
        echo "$label: BYTE-IDENTICAL"
        return 0
    fi
    echo "*** $label DIFFERS ***"
    cmp -l "$a" "$b" | head -20
    echo "differing bytes: $(cmp -l "$a" "$b" | wc -l)"
    return 1
}

# --- The ROM image ----------------------------------------------------------------------------------------------------

if [ "$overlay" -eq 1 ]; then
    mkdir -p "$work/overlay"
    cp "$root"/*.asm "$work/overlay/"
    cp "$here"/*.asm "$work/overlay/"
    annotated_dir="$work/overlay"
    note=" (overlay)"
else
    annotated_dir=$here
    note=""
fi

build "$root" samrom.asm "$work/orig.bin" "ORIGINAL" || exit 1
build "$annotated_dir" samrom.asm "$work/anno.bin" "ANNOTATED" || exit 1

count=$(ls "$here"/*.asm | wc -l)
compare "$work/orig.bin" "$work/anno.bin" "samrom.asm$note  ($count annotated files)" || status=1

# --- romtest.asm, which samrom.asm does not include --------------------------------------------------------------------

if [ -f "$here/romtest.asm" ]; then
    build "$root" romtest.asm "$work/rt_orig.bin" "ORIGINAL romtest" || exit 1
    build "$annotated_dir" romtest.asm "$work/rt_anno.bin" "ANNOTATED romtest" || exit 1
    compare "$work/rt_orig.bin" "$work/rt_anno.bin" "romtest.asm" || status=1
fi

# --- Static equivalence check -------------------------------------------------------------------------------------------

if [ "$verify" -eq 1 ] && [ -f "$here/verify_annotated.py" ]; then
    echo
    if out=$(cd "$root" && python "$here/verify_annotated.py" . "$here" 2>&1); then
        echo "verify_annotated.py: $(echo "$out" | tail -1)"
    else
        # Print each mismatch block: the "** MISMATCH" line and the differing lines under it, but not the
        # per-file OK lines that follow.
        echo "$out" | awk '/\*\* MISMATCH/ {show=1} /^  (OK|--) / {show=0} show'
        echo "verify_annotated.py: $(echo "$out" | tail -1)"
        status=1
    fi
fi

if [ "$keep" -eq 1 ]; then
    echo
    echo "build directory kept at $work"
fi

exit $status
