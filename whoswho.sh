#!/usr/bin/env bash
#
# whoswho.sh - Interactive nmap wrapper with auto subnet detection & indexed logging
#
# Educational tool: prompts before each scan stage, shows the exact command
# being run, and saves output to indexed, timestamped files for later
# correlation/parsing by other tools.
#
# USAGE: ./whoswho.sh
#
set -uo pipefail

# ---------- Config ----------
# Output goes under /tmp so results are automatically cleared on reboot
# (systemd-tmpfiles / most distros clear /tmp on boot). Change OUTDIR
# below if you want scans to persist instead.
OUTDIR="/tmp/whoswho_scans"
TS="$(date +%Y%m%d_%H%M%S)"
SESSION_DIR="${OUTDIR}/session_${TS}"
INDEX_FILE="${SESSION_DIR}/00_index.txt"
STEP=0

mkdir -p "$SESSION_DIR"

# ---------- Helpers ----------

color() { # color "31" "text"
    printf "\033[%sm%s\033[0m\n" "$1" "$2"
}

banner() {
    color "36" "============================================================"
    color "36" " $1"
    color "36" "============================================================"
}

confirm() { # confirm "prompt text" -> returns 0 for yes
    local prompt="$1"
    local ans
    read -r -p "$(color '33' "$prompt [y/N]: ")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

ask() { # ask "prompt text" "default" -> echoes value
    local prompt="$1" default="$2" ans
    read -r -p "$(color '33' "$prompt [$default]: ")" ans
    echo "${ans:-$default}"
}

next_index() {
    STEP=$((STEP + 1))
    printf "%02d" "$STEP"
}

run_step() {
    # run_step "label" "command_string" "output_suffix"
    local label="$1" cmd="$2" suffix="$3"
    local idx
    idx="$(next_index)"
    local outfile="${SESSION_DIR}/${idx}_${suffix}.txt"

    banner "STEP $idx: $label"
    color "35" "COMMAND TO RUN:"
    echo "  $cmd"
    echo

    if ! confirm "Run this command now?"; then
        color "31" "Skipped."
        echo "[SKIPPED] $cmd" >> "$INDEX_FILE"
        return
    fi

    echo ">>> Running... output -> $outfile"
    {
        echo "# Command : $cmd"
        echo "# Started : $(date -Iseconds)"
        echo "# ------------------------------------------------------------"
    } > "$outfile"

    # Run and tee to both screen and file
    eval "$cmd" 2>&1 | tee -a "$outfile"

    echo "# Finished: $(date -Iseconds)" >> "$outfile"

    echo "${idx} | ${label} | ${cmd} | ${outfile}" >> "$INDEX_FILE"
    color "32" "Saved: $outfile"
    summarize_output "$outfile"
    echo
}

summarize_output() {
    # Pulls the useful bits out of an nmap output file and prints a
    # short, readable recap (host, state, open ports/services, OS guess).
    local file="$1"
    local hosts open_lines os_lines

    color "34" "---------------------- SUMMARY ----------------------"

    hosts=$(grep -E "^Nmap scan report for" "$file" 2>/dev/null)
    if [[ -n "$hosts" ]]; then
        echo "$hosts" | while IFS= read -r line; do
            color "36" "Host: ${line#Nmap scan report for }"
        done
    fi

    open_lines=$(grep -E "^[0-9]+/(tcp|udp)\s+open" "$file" 2>/dev/null)
    if [[ -n "$open_lines" ]]; then
        printf "%-12s %-10s %s\n" "PORT" "STATE" "SERVICE/VERSION"
        echo "$open_lines" | while IFS= read -r line; do
            port=$(awk '{print $1}' <<< "$line")
            state=$(awk '{print $2}' <<< "$line")
            svc=$(cut -d' ' -f3- <<< "$line" | sed 's/^ *//')
            printf "%-12s " "$port"
            color "32" "$(printf '%-10s %s' "$state" "$svc")"
        done
    fi

    os_lines=$(grep -E "^(OS details|Running|Aggressive OS guesses)" "$file" 2>/dev/null)
    if [[ -n "$os_lines" ]]; then
        echo "$os_lines" | while IFS= read -r line; do
            color "35" "$line"
        done
    fi

    if [[ -z "$hosts" && -z "$open_lines" && -z "$os_lines" ]]; then
        color "33" "(no notable results parsed — see full file for raw output)"
    fi

    color "34" "-------------------------------------------------------"
}

require_root_note() {
    if [[ $EUID -ne 0 ]]; then
        color "33" "Note: not running as root — SYN scans (-sS) and OS detection (-O) will fall back to TCP connect scans or may fail. Consider sudo for full functionality."
        echo
    fi
}

# ---------- Start ----------

command -v nmap >/dev/null 2>&1 || { color "31" "nmap not found. Install it first (sudo apt install nmap)."; exit 1; }

banner "Who's Who - Interactive Nmap Recon Wrapper"
echo
color "31" "DISCLAIMER: Only scan networks and hosts you own or have explicit,"
color "31" "written authorization to test. Unauthorized scanning may violate"
color "31" "the Computer Fraud and Abuse Act (or local equivalent) and other laws."
echo
if ! confirm "I confirm I am authorized to scan the target network"; then
    color "31" "Authorization not confirmed. Exiting."
    exit 1
fi
echo

echo "Session output directory: $SESSION_DIR"
echo "# Who's Who session $TS" > "$INDEX_FILE"
echo "# idx | label | command | outfile" >> "$INDEX_FILE"
require_root_note

# ---------- Auto-detect gateway / interface / subnet ----------

banner "Network Auto-Detection"

DEFAULT_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
DEFAULT_GW="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"

if [[ -n "${DEFAULT_IFACE:-}" ]]; then
    CIDR="$(ip -o -f inet addr show "$DEFAULT_IFACE" 2>/dev/null | awk '{print $4; exit}')"
else
    CIDR=""
fi

echo "Detected interface : ${DEFAULT_IFACE:-none found}"
echo "Detected gateway    : ${DEFAULT_GW:-none found}"
echo "Detected local CIDR : ${CIDR:-none found}"
echo

if [[ -z "$CIDR" ]]; then
    color "31" "Could not auto-detect a subnet."
    CIDR="$(ask "Enter target subnet manually (CIDR notation)" "192.168.1.0/24")"
else
    if ! confirm "Use detected subnet $CIDR for scanning?"; then
        CIDR="$(ask "Enter target subnet" "$CIDR")"
    fi
fi

TARGET="$CIDR"
echo "Target set to: $TARGET"
echo

# ---------- Scan stages ----------

banner "Scan Plan"
cat <<EOF
Choose which stages to run against $TARGET. You'll still be shown the
exact nmap command and asked to confirm before each one actually runs.

  1) Host discovery (ping sweep)          - find live hosts
  2) Fast port scan (top 100 ports)       - quick TCP scan on live hosts
  3) Service/version detection            - -sV on discovered open ports
  4) OS detection                         - -O (best effort, needs root)
  5) Full TCP port scan (slow)            - -p- all 65535 ports
  6) Script scan (default NSE scripts)    - -sC on top ports

All output is saved to: $SESSION_DIR
An index file correlating steps to commands is at: $INDEX_FILE
EOF
echo
color "33" "Enter the stage numbers you want to run, e.g. '1,2,3' or '1-4',"
color "33" "or 'all' to run every stage. Note: stages 2-6 use live hosts from"
color "33" "stage 1 if it was selected and run first; otherwise they scan the full target."
echo

SELECTION="$(ask "Stages to run" "all")"

declare -A RUN_STAGE=( [1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 )

if [[ "$SELECTION" == "all" || "$SELECTION" == "All" || "$SELECTION" == "ALL" ]]; then
    for n in 1 2 3 4 5 6; do RUN_STAGE[$n]=1; done
else
    # Support comma-separated list and ranges like 1-4
    IFS=',' read -ra PARTS <<< "$SELECTION"
    for part in "${PARTS[@]}"; do
        part="$(echo "$part" | tr -d '[:space:]')"
        if [[ "$part" =~ ^([1-6])-([1-6])$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            for ((n=start; n<=end; n++)); do RUN_STAGE[$n]=1; done
        elif [[ "$part" =~ ^[1-6]$ ]]; then
            RUN_STAGE[$part]=1
        elif [[ -n "$part" ]]; then
            color "31" "Ignoring unrecognized entry: '$part'"
        fi
    done
fi

CHOSEN=""
for n in 1 2 3 4 5 6; do
    [[ "${RUN_STAGE[$n]}" == "1" ]] && CHOSEN="${CHOSEN}${n} "
done
if [[ -z "$CHOSEN" ]]; then
    color "31" "No valid stages selected. Exiting."
    exit 0
fi
echo "Selected stages: $CHOSEN"
echo

if ! confirm "Proceed with the selected stages against $TARGET?"; then
    color "31" "Aborted by user."
    exit 0
fi

SCAN_TARGET="$TARGET"

# Stage 1: Host discovery
if [[ "${RUN_STAGE[1]}" == "1" ]]; then
    run_step "Host discovery (ping sweep)" \
        "nmap -sn '$TARGET' -oN '${SESSION_DIR}/tmp_discovery.txt'" \
        "host_discovery"

    LIVE_HOSTS_FILE="${SESSION_DIR}/live_hosts.txt"
    if [[ -f "${SESSION_DIR}/tmp_discovery.txt" ]]; then
        grep -oP '(?<=Nmap scan report for )[\d\.]+' "${SESSION_DIR}/tmp_discovery.txt" \
            > "$LIVE_HOSTS_FILE" 2>/dev/null || true
        rm -f "${SESSION_DIR}/tmp_discovery.txt"
    fi

    if [[ -s "$LIVE_HOSTS_FILE" ]]; then
        HOST_COUNT=$(wc -l < "$LIVE_HOSTS_FILE")
        color "32" "Found $HOST_COUNT live host(s). Saved to $LIVE_HOSTS_FILE"
        SCAN_TARGET="$(paste -sd, "$LIVE_HOSTS_FILE")"
    else
        color "33" "No live hosts parsed (hosts may block ping). Falling back to full target for remaining stages."
    fi
    echo
fi

# Stage 2: Fast port scan
if [[ "${RUN_STAGE[2]}" == "1" ]]; then
    run_step "Fast port scan (top 100 ports)" \
        "nmap -T4 --top-ports 100 -oN '${SESSION_DIR}/tmp_fastports.txt' $SCAN_TARGET" \
        "fast_port_scan"
fi

# Stage 3: Service/version detection
if [[ "${RUN_STAGE[3]}" == "1" ]]; then
    run_step "Service/version detection" \
        "nmap -sV -T4 -oN '${SESSION_DIR}/tmp_serviceversion.txt' $SCAN_TARGET" \
        "service_version"
fi

# Stage 4: OS detection
if [[ "${RUN_STAGE[4]}" == "1" ]]; then
    run_step "OS detection" \
        "nmap -O -T4 -oN '${SESSION_DIR}/tmp_osdetect.txt' $SCAN_TARGET" \
        "os_detection"
fi

# Stage 5: Full TCP port scan (slow)
if [[ "${RUN_STAGE[5]}" == "1" ]]; then
    run_step "Full TCP port scan (all 65535 ports)" \
        "nmap -p- -T4 -oN '${SESSION_DIR}/tmp_fullports.txt' $SCAN_TARGET" \
        "full_port_scan"
fi

# Stage 6: Default script scan
if [[ "${RUN_STAGE[6]}" == "1" ]]; then
    run_step "Default NSE script scan (top ports)" \
        "nmap -sC -T4 -oN '${SESSION_DIR}/tmp_scriptscan.txt' $SCAN_TARGET" \
        "script_scan"
fi

# ---------- Wrap up ----------

banner "Session Complete"
echo "All results saved under: $SESSION_DIR"
echo "Index of steps: $INDEX_FILE"
echo
column -t -s'|' "$INDEX_FILE" 2>/dev/null || cat "$INDEX_FILE"
echo
color "32" "Done."
