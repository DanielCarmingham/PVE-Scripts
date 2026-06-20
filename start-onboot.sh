#!/bin/bash

# Resolve the script's directory and its shared library directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LIB_DIR="$SCRIPT_DIR/lib"

# Source the colors file from the lib directory
if [ -f "$LIB_DIR/colors.sh" ]; then
    source "$LIB_DIR/colors.sh"
else
    # Fallback definitions if colors.sh is missing
    NOCOLOR='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    LIGHTRED='\033[1;31m'
fi

# Shared guest-enumeration helpers (required)
if [ -f "$LIB_DIR/onboot-lib.sh" ]; then
    source "$LIB_DIR/onboot-lib.sh"
else
    echo -e "${RED}[X] Required file onboot-lib.sh not found in $LIB_DIR${NOCOLOR}" >&2
    exit 1
fi


# ==============================================================================
# HEADER & INFO
# ==============================================================================
echo -e ""
echo -e "${BLUE}======================================================================${NOCOLOR}"
echo -e "${PURPLE}                 PROXMOX ONBOOT GUEST MANAGER                        ${NOCOLOR}"
echo -e "${BLUE}======================================================================${NOCOLOR}"
echo -e ""


# ==============================================================================
# CONFIRMATION LOGIC
# ==============================================================================
SKIP_CONFIRM=false
if [ "$1" == "-y" ]; then
    SKIP_CONFIRM=true
fi

if [ "$SKIP_CONFIRM" = true ]; then
    echo -e "${GREEN}[+] Confirmation bypassed (${RED}-y${GREEN} flag detected).${NOCOLOR}"
    echo -e ""
else
    echo -e "${CYAN}Tip: You can bypass confirmation prompts by running with the ${RED}-y${CYAN} flag.${NOCOLOR}"
    echo -e "     ${LIGHTRED}Example: ./start-onboot.sh -y${NOCOLOR}"
    echo -e ""

    echo -e "${RED}[!] WARNING:${PURPLE} This action will start ALL guests (containers and VMs) configured to boot on host startup.${NOCOLOR}"
    echo -e ""

    read -p "    Are you sure you want to proceed? (y/N): " response
    echo -e ""

    case "$response" in
        [yY][eE][sS]|[yY])
            echo -e "${GREEN}[+] Proceeding with guest initialization...${NOCOLOR}"
            echo -e ""
            ;;
        *)
            echo -e "${RED}[X] Operation canceled by user.${NOCOLOR}"
            echo -e ""
            exit 0
            ;;
    esac
fi


# ==============================================================================
# EXECUTION PHASE
# ==============================================================================
echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e "${CYAN}[*] Scanning Proxmox node for on-boot configuration tags...${NOCOLOR}"
echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e ""


# How many guests to start at once (override with ONBOOT_PARALLEL=N).
MAX_PARALLEL="${ONBOOT_PARALLEL:-8}"

# Abort cleanly on Ctrl+C: kill in-flight starts and their pct/qm children.
trap 'trap - INT TERM; echo -e "\n${RED}[!] Interrupted — aborting and killing in-flight operations...${NOCOLOR}"; kill_workers; exit 130' INT TERM

# Worker run in a background job by run_parallel. Emits exactly one line so
# concurrent output never interleaves mid-line. Args: <type> <vmid> <name>
start_worker() {
    local label="${CYAN}$3 ${BLUE}(${1^^} $2)${NOCOLOR}"
    local t0; t0=$(now_ms)
    start_guest "$1" "$2" >/dev/null 2>&1; local rc=$?
    local dt; dt=$(fmt_elapsed "$t0" "$(now_ms)")
    if [ "$rc" -eq 0 ]; then
        echo -e "${GREEN}✔ Started: $label ${CYAN}(${dt}s)${NOCOLOR}"
    else
        echo -e "${RED}✘ Failed: $label ${CYAN}(${dt}s)${NOCOLOR}"
    fi
}

# --- Phase 1: classify (fast, ordered) -------------------------------------
# Print skips/already-running immediately; queue the rest for parallel start.
TODO=()
while IFS=$'\t' read -r type vmid status onboot template name; do
    label="${CYAN}$name ${BLUE}(${type^^} $vmid)${NOCOLOR}"

    # Template — skip
    if [ "$template" = "1" ]; then
        echo -e "${YELLOW}⊘ Skipping (template): $label"
        continue
    fi

    # Not set to boot on start — note and skip
    if [ "$onboot" != "1" ]; then
        echo -e "${YELLOW}⊘ Skipping (onboot off): $label"
        continue
    fi

    # Already up
    if [ "$status" = "running" ]; then
        echo -e "${GREEN}✔ Already running: $label"
        continue
    fi

    TODO+=("$type"$'\t'"$vmid"$'\t'"$name")
done < <(enumerate_guests)

# --- Phase 2: start queued guests in parallel ------------------------------
echo -e ""
if [ "${#TODO[@]}" -eq 0 ]; then
    echo -e "${CYAN}[*] No guests need starting.${NOCOLOR}"
else
    echo -e "${CYAN}[*] Starting ${#TODO[@]} guest(s), up to ${MAX_PARALLEL} at a time...${NOCOLOR}"
    echo -e ""
    phase_t0=$(now_ms)
    run_parallel "$MAX_PARALLEL" start_worker < <(printf '%s\n' "${TODO[@]}")
    echo -e ""
    echo -e "${CYAN}[*] Total time: (${PURPLE}$(fmt_elapsed "$phase_t0" "$(now_ms)")s${CYAN})${NOCOLOR}"
fi
echo -e ""

echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e "${GREEN}[✓] Finished processing all on-boot guests!${NOCOLOR}"
echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e ""
