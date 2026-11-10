#!/usr/bin/env bash
# Zynx_integrity - lightweight Bash File Integrity Monitor
# Requires Bash 4+, find, sha256sum, sort, comm, diff, awk, coreutils.

set -o pipefail
umask 077

APP_NAME="Zynx_integrity"
VERSION="1.0.0"
START_EPOCH=$SECONDS

DEFAULT_DIRS=(/bin /sbin /usr/bin /usr/sbin /usr/local/bin /etc)
DB_PATH="${ZYNX_DB:-/var/lib/zynx_integrity/baseline.tsv}"
WORK_DIR=""
LAST_STATUS="Not scanned yet"
LAST_SUMMARY="Create a baseline to begin monitoring."

# ---------- Terminal helpers ----------
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; RED=$'\033[31m'; MAGENTA=$'\033[35m'

supports_color() {
    [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]
}
if ! supports_color; then
    RESET=""; BOLD=""; DIM=""; CYAN=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; MAGENTA=""
fi

cleanup() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT INT TERM

elapsed() {
    local s=$SECONDS h m sec
    h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
    printf '%02d:%02d:%02d' "$h" "$m" "$sec"
}

line() { printf '%s\n' "${DIM}────────────────────────────────────────────────────────────────────────${RESET}"; }
box() {
    local kind="$1"; shift
    local color="$CYAN"
    case "$kind" in success) color="$GREEN";; warning) color="$YELLOW";; error) color="$RED";; info) color="$CYAN";; esac
    printf '\n%s┌─ %s%s\n' "$color" "$*" "$RESET"
    printf '%s└────────────────────────────────────────────────────────────────────────%s\n' "$color" "$RESET"
}
msg() { printf '  %b\n' "$*"; }
pause() { printf '\n  %sPress Enter to continue...%s' "$DIM" "$RESET"; IFS= read -r _; }

draw_header() {
    clear 2>/dev/null || true
    printf '%s%s┌────────────────────────────────────────────────────────────────────────┐%s\n' "$BLUE" "$BOLD" "$RESET"
    printf '%s│%s  %-24s %s%-18s%s %s│%s\n' "$BLUE" "$RESET" "$APP_NAME" "$MAGENTA" "zynx" "$RESET" "RUN TIME: $(elapsed)" "$BLUE" "$RESET"
    printf '%s│%s  %-68s%s│%s\n' "$BLUE" "$RESET" "Lightweight File Integrity Monitor  •  v$VERSION" "$BLUE" "$RESET"
    printf '%s└────────────────────────────────────────────────────────────────────────┘%s\n' "$BLUE" "$RESET"
    printf '  Database: %s\n' "$DB_PATH"
    printf '  Status:   %b\n' "$LAST_STATUS"
    line
}

usage() {
cat <<EOF
$APP_NAME v$VERSION
Bash-only lightweight File Integrity Monitor.

Usage:
  $0                 Launch interactive TUI
  $0 --init          Create/replace the trusted baseline
  $0 --check         Compare the system against the baseline
  $0 --show-dirs     Show monitored directories
  $0 --help          Show this help

Environment:
  ZYNX_DB=/path/to/baseline.tsv   Override baseline database path

Default monitored directories:
  ${DEFAULT_DIRS[*]}

Run as root to read all system files. The baseline should be created on a
known-clean system and stored somewhere attackers cannot modify.
EOF
}

show_dirs() {
    box info "MONITORED DIRECTORIES"
    for d in "${DEFAULT_DIRS[@]}"; do
        if [[ -d "$d" ]]; then msg "${GREEN}[+]${RESET} $d"
        else msg "${YELLOW}[-]${RESET} $d (missing or inaccessible)"; fi
    done
    pause
}

# ---------- Scan engine ----------
prepare_workdir() {
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zynx-integrity.XXXXXX")" || {
        box error "Could not create temporary workspace"; return 1;
    }
    chmod 700 "$WORK_DIR"
}

build_manifest() {
    # Output is a sorted TSV: absolute_path<TAB>sha256.
    # Filenames containing TAB/newline are skipped because TSV cannot represent
    # them unambiguously. All other ordinary Linux filenames are supported.
    local output="$1" list="$WORK_DIR/files.list0" errors="$WORK_DIR/find-errors.log"
    local d file result hash count=0 skipped=0 failures=0
    : > "$list"; : > "$errors"; : > "$output"

    for d in "${DEFAULT_DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        if ! find "$d" -type f -print0 >> "$list" 2>> "$errors"; then
            failures=$((failures + 1))
        fi
    done

    while IFS= read -r -d '' file; do
        if [[ "$file" == *$'\t'* || "$file" == *$'\n'* ]]; then
            skipped=$((skipped + 1)); continue
        fi
        if [[ ! -r "$file" ]]; then
            failures=$((failures + 1)); continue
        fi
        result="$(sha256sum -- "$file" 2>/dev/null)" || {
            failures=$((failures + 1)); continue;
        }
        hash="${result%% *}"
        [[ "$hash" =~ ^[a-fA-F0-9]{64}$ ]] || {
            failures=$((failures + 1)); continue;
        }
        printf '%s\t%s\n' "$file" "$hash" >> "$output"
        count=$((count + 1))
    done < "$list"

    LC_ALL=C sort -t $'\t' -k1,1 -o "$output" "$output"
    SCAN_COUNT=$count
    SCAN_SKIPPED=$skipped
    SCAN_FAILURES=$failures
    SCAN_ERRORS="$errors"
}

initialize_baseline() {
    if [[ $EUID -ne 0 && "$DB_PATH" == /var/lib/* ]]; then
        box warning "Root privileges recommended"
        msg "The default database is under /var/lib. Run with sudo, or set ZYNX_DB"
        msg "to a location you own."
        pause
        return 1
    fi

    if [[ -f "$DB_PATH" ]]; then
        box warning "Existing baseline found"
        msg "Replacing it changes what the tool considers trusted."
        printf '  Type REBUILD to confirm: '
        IFS= read -r answer
        [[ "$answer" == "REBUILD" ]] || { msg "Cancelled."; pause; return 1; }
    fi

    prepare_workdir || return 1
    box info "BUILDING BASELINE"
    msg "Scanning: ${DEFAULT_DIRS[*]}"
    msg "Hashing files with SHA-256. This can take a while on large systems..."
    local temp="$WORK_DIR/new-baseline.tsv"
    build_manifest "$temp"

    if (( SCAN_COUNT == 0 )); then
        box error "No files were hashed; baseline was not written."
        pause; return 1
    fi

    mkdir -p -- "$(dirname -- "$DB_PATH")" || {
        box error "Cannot create database directory: $(dirname -- "$DB_PATH")"; pause; return 1;
    }
    chmod 700 "$(dirname -- "$DB_PATH")" 2>/dev/null || true
    install -m 600 -- "$temp" "$DB_PATH" || {
        box error "Could not install baseline at $DB_PATH"; pause; return 1;
    }

    LAST_STATUS="${GREEN}BASELINE CREATED${RESET}"
    LAST_SUMMARY="$SCAN_COUNT files recorded; $SCAN_FAILURES scan/read errors; $SCAN_SKIPPED unsupported filenames skipped."
    box success "BASELINE CREATED"
    msg "${GREEN}Files recorded:${RESET} $SCAN_COUNT"
    msg "Scan/read errors: $SCAN_FAILURES"
    msg "Skipped TAB/newline filenames: $SCAN_SKIPPED"
    msg "Database permissions: 600"
    if (( SCAN_FAILURES > 0 )); then
        msg "${YELLOW}Some files could not be read. Review errors before trusting this baseline.${RESET}"
        [[ -s "$SCAN_ERRORS" ]] && sed -n '1,8p' "$SCAN_ERRORS" | sed 's/^/    /'
    fi
    pause
}

check_integrity() {
    if [[ ! -s "$DB_PATH" ]]; then
        box error "Baseline database not found"
        msg "Create a baseline first using menu option 1 or: $0 --init"
        pause; return 1
    fi
    prepare_workdir || return 1
    box info "CHECKING FILE INTEGRITY"
    msg "Re-hashing monitored files..."
    local current="$WORK_DIR/current.tsv"
    build_manifest "$current"

    local old_paths="$WORK_DIR/old.paths" new_paths="$WORK_DIR/new.paths"
    local removed="$WORK_DIR/removed.paths" added="$WORK_DIR/added.paths"
    local changed="$WORK_DIR/changed.tsv" diffout="$WORK_DIR/diff.txt"
    cut -f1 "$DB_PATH" > "$old_paths"
    cut -f1 "$current" > "$new_paths"
    comm -23 "$old_paths" "$new_paths" > "$removed"
    comm -13 "$old_paths" "$new_paths" > "$added"

    awk -F '\t' '
        NR==FNR { old[$1]=$2; next }
        ($1 in old) && old[$1] != $2 { printf "%s\t%s\t%s\n", $1, old[$1], $2 }
    ' "$DB_PATH" "$current" > "$changed"

    diff -u "$DB_PATH" "$current" > "$diffout" || true

    local n_removed n_added n_changed
    n_removed=$(wc -l < "$removed")
    n_added=$(wc -l < "$added")
    n_changed=$(wc -l < "$changed")

    LAST_SUMMARY="Changed: $n_changed | Removed: $n_removed | Added: $n_added | Scan/read errors: $SCAN_FAILURES"
    if (( n_removed + n_added + n_changed == 0 && SCAN_FAILURES == 0 )); then
        LAST_STATUS="${GREEN}CLEAN — NO DIFFERENCES${RESET}"
        box success "INTEGRITY CHECK PASSED"
        msg "${GREEN}No changes detected.${RESET} $SCAN_COUNT files checked."
    else
        LAST_STATUS="${RED}ALERT — DIFFERENCES FOUND${RESET}"
        box error "INTEGRITY ALERT"
        msg "${RED}Detected differences. Investigate before trusting this system.${RESET}"
        printf '\n  %sChanged files (%s):%s\n' "$YELLOW" "$n_changed" "$RESET"
        if (( n_changed > 0 )); then
            while IFS=$'\t' read -r path oldhash newhash; do
                printf '    %s[CHANGED]%s %s\n      old: %s\n      new: %s\n' "$RED" "$RESET" "$path" "$oldhash" "$newhash"
            done < "$changed"
        fi
        printf '\n  %sRemoved files (%s):%s\n' "$YELLOW" "$n_removed" "$RESET"
        (( n_removed == 0 )) || sed 's/^/    [REMOVED] /' "$removed"
        printf '\n  %sNew files (%s):%s\n' "$YELLOW" "$n_added" "$RESET"
        (( n_added == 0 )) || sed 's/^/    [NEW]     /' "$added"
        if (( SCAN_FAILURES > 0 )); then
            printf '\n  %sScan/read errors: %s%s\n' "$YELLOW" "$SCAN_FAILURES" "$RESET"
            [[ -s "$SCAN_ERRORS" ]] && sed -n '1,8p' "$SCAN_ERRORS" | sed 's/^/    /'
        fi
    fi
    msg "Files hashed: $SCAN_COUNT | Skipped unusual filenames: $SCAN_SKIPPED"
    msg "A unified diff was generated internally for this check."
    pause
}

show_database_info() {
    box info "BASELINE DATABASE"
    if [[ -f "$DB_PATH" ]]; then
        msg "Path: $DB_PATH"
        msg "Size: $(du -h "$DB_PATH" 2>/dev/null | awk '{print $1}')"
        msg "Recorded files: $(wc -l < "$DB_PATH")"
        msg "Permissions: $(stat -c '%a' "$DB_PATH" 2>/dev/null || printf 'unknown')"
        msg "Last modified: $(stat -c '%y' "$DB_PATH" 2>/dev/null || printf 'unknown')"
    else
        msg "No baseline exists yet."
    fi
    pause
}

interactive_menu() {
    while true; do
        draw_header
        printf '  %s[1]%s Create / rebuild trusted baseline\n' "$GREEN" "$RESET"
        printf '  %s[2]%s Run integrity check\n' "$CYAN" "$RESET"
        printf '  %s[3]%s Show monitored directories\n' "$CYAN" "$RESET"
        printf '  %s[4]%s Baseline database information\n' "$CYAN" "$RESET"
        printf '  %s[5]%s Exit\n' "$RED" "$RESET"
        line
        printf '  Select an option: '
        IFS= read -r choice || break
        case "$choice" in
            1) initialize_baseline ;;
            2) check_integrity ;;
            3) show_dirs ;;
            4) show_database_info ;;
            5|q|Q) printf '\n  %sZynx_integrity closed. Total runtime: %s%s\n' "$MAGENTA" "$(elapsed)" "$RESET"; break ;;
            *) box warning "Invalid option"; pause ;;
        esac
    done
}

case "${1:-}" in
    --init) initialize_baseline ;;
    --check) check_integrity ;;
    --show-dirs) show_dirs ;;
    --help|-h) usage ;;
    --tui|"") interactive_menu ;;
    *) usage; exit 2 ;;
esac
