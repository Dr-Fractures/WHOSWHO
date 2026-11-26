#!/usr/bin/env bash
#
# whoswho.sh - Interactive nmap wrapper with auto subnet detection & indexed logging
#
# Educational tool: shows the exact command being run and saves output to
# indexed, timestamped files for later correlation/parsing by other tools.
#
# USAGE: ./whoswho.sh
#   WHOSWHO_OUTDIR=/path ./whoswho.sh    override the output location
#
# Stage selection:
#   all          host discovery + ONE combined nmap command, no per-step prompts
#   1,2,7 / 1-4  chosen stages, each confirmed individually
#
# Note: no `set -e` on purpose. Failed scans and declined prompts are
# expected and handled explicitly.
set -uo pipefail

# ---------- Config ----------
# Default output is under /tmp so results are cleared on reboot.
# Set WHOSWHO_OUTDIR to persist scans elsewhere.
OUTDIR="${WHOSWHO_OUTDIR:-/tmp/whoswho_scans}"
TS="$(date +%Y%m%d_%H%M%S)"
SESSION_DIR="${OUTDIR}/session_${TS}"
INDEX_FILE="${SESSION_DIR}/00_index.txt"
STEP=0
LAST_OUTFILE=""
ALL_MODE=0        # 1 when the user picked "all"
AUTO_CONFIRM=0    # 1 = skip the per-step "Run this command now?" prompt

# The "all" one-liner. -O needs root, so it's added only when running as root.
ALL_FLAGS="-sV -sC -p- -T4"
[[ $EUID -eq 0 ]] && ALL_FLAGS+=" -O"

# ---------- Stage table ----------
# To add a preset: bump MAX_STAGE and add one line to each array.
# STAGE_ROOT=1 means the stage is skipped when not running as root.
# Stage 1 (host discovery) is special-cased; stage 14 prompts for custom flags.
MAX_STAGE=14
CUSTOM_STAGE=14

declare -A STAGE_LABEL=(
    [1]="Host discovery (ping sweep)"
    [2]="Fast port scan (top 100 ports)"
    [3]="Service/version detection"
    [4]="OS detection"
    [5]="Full TCP port scan (all 65535 ports)"
    [6]="Default NSE script scan"
    [7]="Service + default scripts"
    [8]="Service + default scripts, all ports"
    [9]="Aggressive scan"
    [10]="Aggressive scan, all ports"
    [11]="Full recon (SYN, version, scripts, OS, all ports)"
    [12]="UDP scan (top 50 ports)"
    [13]="Vulnerability scripts"
    [14]="Custom flags (you type them)"
)
declare -A STAGE_SUFFIX=(
    [1]="host_discovery" [2]="fast_port_scan" [3]="service_version"
    [4]="os_detection"   [5]="full_port_scan" [6]="script_scan"
    [7]="sv_sc"          [8]="sv_sc_allports" [9]="aggressive"
    [10]="aggressive_allports" [11]="full_recon" [12]="udp_top50"
    [13]="vuln_scripts"  [14]="custom"
)
declare -A STAGE_FLAGS=(
    [1]="-sn"
    [2]="-T4 --top-ports 100"
    [3]="-sV -T4"
    [4]="-O -T4"
    [5]="-p- -T4"
    [6]="-sC -T4"
    [7]="-sV -sC -T4"
    [8]="-sV -sC -p- -T4"
    [9]="-A -T4"
    [10]="-A -p- -T4"
    [11]="-sS -sV -sC -O -p- -T4"
    [12]="-sU --top-ports 50 -T4"
    [13]="-sV --script vuln -T4"
    [14]=""
)
declare -A STAGE_ROOT=( [4]=1 [11]=1 [12]=1 )

# ---------- Helpers ----------

color() { # color CODE TEXT
    printf '\033[%sm%s\033[0m\n' "$1" "$2"
}

die() { color "31" "Error: $*" >&2; exit 1; }

banner() {
    color "36" "============================================================"
    color "36" " $1"
    color "36" "============================================================"
}

# Prompts go to stderr so ask() can safely be used in $(...)
confirm() { # confirm "prompt" -> returns 0 for yes
    local ans
    printf '\033[33m%s [y/N]: \033[0m' "$1" >&2
    read -r ans || ans=""
    [[ "$ans" =~ ^[Yy]$ ]]
}

ask() { # ask "prompt" "default" -> echoes value
    local ans
    printf '\033[33m%s [%s]: \033[0m' "$1" "$2" >&2
    read -r ans || ans=""
    echo "${ans:-$2}"
}

# Allow IPv4/IPv6/hostname/CIDR/range characters only; no leading dash
# so input can never be parsed as an nmap option.
valid_target() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]]
}

# Custom nmap flags: letters, digits, space and a few safe punctuation chars.
valid_flags() {
    [[ "$1" =~ ^-[A-Za-z0-9\ ._,:=/-]*$ ]]
}

print_menu() {
    local n root_tag
    for n in $(seq 1 "$MAX_STAGE"); do
        root_tag=""
        [[ "${STAGE_ROOT[$n]:-0}" == "1" ]] && root_tag="  [root]"
        if [[ "$n" == "$CUSTOM_STAGE" ]]; then
            printf '  %2d) %-48s nmap <your flags>\n' "$n" "${STAGE_LABEL[$n]}"
        else
            printf '  %2d) %-48s nmap %s%s\n' "$n" "${STAGE_LABEL[$n]}" "${STAGE_FLAGS[$n]}" "$root_tag"
        fi
    done
    printf '  all) %-47s nmap -sn, then nmap %s\n' "Auto-run, no per-step prompts" "$ALL_FLAGS"
}

summarize_output() {
    # Prints a short recap (hosts, open ports/services, OS guess) from an nmap output file.
    local file="$1"
    local hosts open_lines os_lines line port state svc

    color "34" "---------------------- SUMMARY ----------------------"

    hosts=$(grep -E "^Nmap scan report for" "$file" 2>/dev/null || true)
    if [[ -n "$hosts" ]]; then
        while IFS= read -r line; do
            color "36" "Host: ${line#Nmap scan report for }"
        done <<< "$hosts"
    fi

    open_lines=$(grep -E "^[0-9]+/(tcp|udp)[[:space:]]+open" "$file" 2>/dev/null || true)
    if [[ -n "$open_lines" ]]; then
        printf "%-12s %-10s %s\n" "PORT" "STATE" "SERVICE/VERSION"
        while IFS= read -r line; do
            read -r port state svc <<< "$line"
            printf "%-12s " "$port"
            color "32" "$(printf '%-10s %s' "$state" "$svc")"
        done <<< "$open_lines"
    fi

    os_lines=$(grep -E "^(OS details|Running|Aggressive OS guesses)" "$file" 2>/dev/null || true)
    if [[ -n "$os_lines" ]]; then
        while IFS= read -r line; do
            color "35" "$line"
        done <<< "$os_lines"
    fi

    if [[ -z "$hosts" && -z "$open_lines" && -z "$os_lines" ]]; then
        color "33" "(no notable results parsed - see full file for raw output)"
    fi

    color "34" "-------------------------------------------------------"
}

run_step() {
    # run_step "label" "output_suffix" cmd [args...]
    # Sets LAST_OUTFILE to the saved output path, or "" if skipped.
    # Skips the per-step prompt when AUTO_CONFIRM=1.
    local label="$1" suffix="$2"
    shift 2
    local -a cmd=("$@")
    local idx cmd_str outfile status

    # Increment here, not in a $(...) subshell, or STEP never advances.
    STEP=$((STEP + 1))
    printf -v idx '%02d' "$STEP"
    outfile="${SESSION_DIR}/${idx}_${suffix}.txt"
    printf -v cmd_str '%q ' "${cmd[@]}"
    cmd_str="${cmd_str% }"
    LAST_OUTFILE=""

    banner "STEP $idx: $label"
    color "35" "COMMAND TO RUN:"
    echo "  $cmd_str"
    echo

    if [[ "$AUTO_CONFIRM" != "1" ]] && ! confirm "Run this command now?"; then
        color "31" "Skipped."
        echo "${idx} | ${label} | ${cmd_str} | SKIPPED" >> "$INDEX_FILE"
        return 0
    fi

    echo ">>> Running... output -> $outfile"
    {
        echo "# Command : $cmd_str"
        echo "# Started : $(date -Iseconds)"
        echo "# ------------------------------------------------------------"
    } > "$outfile"

    "${cmd[@]}" 2>&1 | tee -a "$outfile"
    status="${PIPESTATUS[0]}"

    echo "# Finished: $(date -Iseconds) (exit $status)" >> "$outfile"
    echo "${idx} | ${label} | ${cmd_str} | ${outfile} | exit=${status}" >> "$INDEX_FILE"

    if [[ "$status" -ne 0 ]]; then
        color "31" "nmap exited with status $status - output may be incomplete."
    fi
    color "32" "Saved: $outfile"
    summarize_output "$outfile"
    echo
    LAST_OUTFILE="$outfile"
}

# ---------- Preflight ----------

command -v nmap >/dev/null 2>&1 || die "nmap not found. Install it first (sudo apt install nmap)."
command -v ip   >/dev/null 2>&1 || die "'ip' (iproute2) not found."

trap 'echo; color "31" "Interrupted."; exit 130' INT

umask 077
mkdir -p "$SESSION_DIR" || die "Cannot create $SESSION_DIR"

# ---------- Start ----------

banner "Who's Who - Interactive Nmap Recon Wrapper"
echo
color "31" "DISCLAIMER: Only scan networks and hosts you own or have explicit,"
color "31" "written authorization to test. Unauthorized scanning may violate"
color "31" "the Computer Fraud and Abuse Act (or local equivalent) and other laws."
echo
if ! confirm "I confirm I am authorized to scan the target network"; then
    color "31" "Authorization not confirmed. Exiting."
    rmdir "$SESSION_DIR" 2>/dev/null
    exit 1
fi
echo

echo "Session output directory: $SESSION_DIR"
{
    echo "# Who's Who session $TS"
    echo "# idx | label | command | outfile | status"
} > "$INDEX_FILE"

if [[ $EUID -ne 0 ]]; then
    color "33" "Note: not running as root - stages marked [root] are skipped, -O is left out of 'all', and SYN scans fall back to TCP connect scans. Use sudo for full functionality."
    echo
fi

# ---------- Auto-detect gateway / interface / subnet ----------

banner "Network Auto-Detection"

DEFAULT_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
DEFAULT_GW="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"
CIDR=""
if [[ -n "$DEFAULT_IFACE" ]]; then
    CIDR="$(ip -o -f inet addr show "$DEFAULT_IFACE" 2>/dev/null | awk '{print $4; exit}')"
fi

echo "Detected interface  : ${DEFAULT_IFACE:-none found}"
echo "Detected gateway    : ${DEFAULT_GW:-none found}"
echo "Detected local CIDR : ${CIDR:-none found}"
echo

if [[ -z "$CIDR" ]]; then
    color "31" "Could not auto-detect a subnet."
    CIDR="$(ask "Enter target subnet manually (CIDR notation)" "192.168.1.0/24")"
elif ! confirm "Use detected subnet $CIDR for scanning?"; then
    CIDR="$(ask "Enter target subnet" "$CIDR")"
fi

valid_target "$CIDR" || die "Invalid target: '$CIDR'"

# Warn on very large IPv4 ranges
if [[ "$CIDR" =~ ^[0-9.]+/([0-9]+)$ ]] && (( BASH_REMATCH[1] < 16 )); then
    color "33" "Warning: /${BASH_REMATCH[1]} covers a very large address space."
    confirm "Continue anyway?" || { color "31" "Aborted."; exit 0; }
fi

TARGET="$CIDR"
echo "Target set to: $TARGET"
echo

# ---------- Scan plan ----------

banner "Scan Plan"
echo "Choose which stages to run against $TARGET."
echo "Individual stages show the exact nmap command and ask before each one."
echo "'all' runs host discovery and one combined scan with no further prompts."
echo
print_menu
echo
echo "All output is saved to: $SESSION_DIR"
echo "An index file correlating steps to commands is at: $INDEX_FILE"
echo
color "33" "Enter stage numbers, e.g. '1,2,7' or '1-4,9', or 'all'."
color "33" "If stage 1 runs, the other stages scan only the live hosts it finds;"
color "33" "otherwise they scan the full target."
echo

SELECTION="$(ask "Stages to run" "all")"

declare -A RUN_STAGE=()
for n in $(seq 1 "$MAX_STAGE"); do RUN_STAGE[$n]=0; done

if [[ "${SELECTION,,}" == "all" ]]; then
    ALL_MODE=1
    AUTO_CONFIRM=1
    RUN_STAGE[1]=1
else
    IFS=',' read -ra PARTS <<< "$SELECTION"
    for part in "${PARTS[@]}"; do
        part="${part//[[:space:]]/}"
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            lo=$((10#${BASH_REMATCH[1]})); hi=$((10#${BASH_REMATCH[2]}))
            if (( lo >= 1 && hi <= MAX_STAGE && lo <= hi )); then
                for ((n = lo; n <= hi; n++)); do RUN_STAGE[$n]=1; done
            else
                color "31" "Ignoring out-of-range entry: '$part'"
            fi
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            n=$((10#$part))
            if (( n >= 1 && n <= MAX_STAGE )); then
                RUN_STAGE[$n]=1
            else
                color "31" "Ignoring out-of-range entry: '$part'"
            fi
        elif [[ -n "$part" ]]; then
            color "31" "Ignoring unrecognized entry: '$part'"
        fi
    done
fi

CHOSEN=""
for n in $(seq 1 "$MAX_STAGE"); do
    [[ "${RUN_STAGE[$n]}" == "1" ]] && CHOSEN+="$n "
done
[[ -n "$CHOSEN" ]] || { color "31" "No valid stages selected. Exiting."; exit 0; }

if [[ "$ALL_MODE" == "1" ]]; then
    echo "Selected: all (auto-run, no per-step prompts)"
    echo "  1) nmap -sn $TARGET"
    echo "  2) nmap $ALL_FLAGS <live hosts, or $TARGET if none found>"
else
    echo "Selected stages: $CHOSEN"
fi
echo
confirm "Proceed against $TARGET?" || { color "31" "Aborted by user."; exit 0; }
echo

# ---------- Run stages ----------

# Targets for later stages: the full target, or -iL <live hosts> after stage 1.
TARGET_ARGS=("$TARGET")

if [[ "${RUN_STAGE[1]}" == "1" ]]; then
    read -ra flags <<< "${STAGE_FLAGS[1]}"
    run_step "${STAGE_LABEL[1]}" "${STAGE_SUFFIX[1]}" nmap "${flags[@]}" "$TARGET"

    if [[ -n "$LAST_OUTFILE" ]]; then
        LIVE_HOSTS_FILE="${SESSION_DIR}/live_hosts.txt"
        # Handles both "report for 10.0.0.5" and "report for name (10.0.0.5)"
        sed -nE \
            -e 's/^Nmap scan report for .*\(([0-9a-fA-F:.]+)\)$/\1/p;t' \
            -e 's/^Nmap scan report for ([0-9a-fA-F:.]+)$/\1/p' \
            "$LAST_OUTFILE" > "$LIVE_HOSTS_FILE"

        if [[ -s "$LIVE_HOSTS_FILE" ]]; then
            color "32" "Found $(wc -l < "$LIVE_HOSTS_FILE") live host(s). Saved to $LIVE_HOSTS_FILE"
            TARGET_ARGS=(-iL "$LIVE_HOSTS_FILE")
        else
            color "33" "No live hosts parsed (hosts may block ping)."
            # An unattended all-ports scan of the whole range is worth one extra check.
            if [[ "$ALL_MODE" == "1" ]]; then
                confirm "Scan the full target $TARGET anyway?" || { color "31" "Aborted."; exit 0; }
            else
                color "33" "Falling back to full target."
            fi
        fi
        echo
    fi
fi

if [[ "$ALL_MODE" == "1" ]]; then
    read -ra flags <<< "$ALL_FLAGS"
    run_step "Combined scan (all)" "all_combined" nmap "${flags[@]}" "${TARGET_ARGS[@]}"
else
    for n in $(seq 2 "$MAX_STAGE"); do
        [[ "${RUN_STAGE[$n]}" == "1" ]] || continue

        if [[ "${STAGE_ROOT[$n]:-0}" == "1" && $EUID -ne 0 ]]; then
            color "33" "Skipping stage $n (${STAGE_LABEL[$n]}): requires root."
            echo
            continue
        fi

        label="${STAGE_LABEL[$n]}"
        flag_str="${STAGE_FLAGS[$n]}"

        if [[ "$n" == "$CUSTOM_STAGE" ]]; then
            flag_str="$(ask "Enter nmap flags (no target)" "-sV -sC -p-")"
            if ! valid_flags "$flag_str"; then
                color "31" "Invalid flags (must start with '-', letters/digits/. , : = / only). Skipping custom stage."
                echo
                continue
            fi
            label="Custom: $flag_str"
        fi

        read -ra flags <<< "$flag_str"
        run_step "$label" "${STAGE_SUFFIX[$n]}" nmap "${flags[@]}" "${TARGET_ARGS[@]}"
    done
fi

# ---------- Wrap up ----------

banner "Session Complete"
echo "All results saved under: $SESSION_DIR"
echo "Index of steps: $INDEX_FILE"
echo
column -t -s'|' "$INDEX_FILE" 2>/dev/null || cat "$INDEX_FILE"
echo
color "32" "Done."
