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
echo -e "${PURPLE}                  PROXMOX ONBOOT GUEST STOPPER                       ${NOCOLOR}"
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
    echo -e "     ${LIGHTRED}Example: ./stop-onboot.sh -y${NOCOLOR}"
    echo -e ""

    echo -e "${RED}[!] WARNING:${PURPLE} This action will shut down ALL on-boot guests (containers and VMs). Running guests that are NOT tagged onboot will be left alone.${NOCOLOR}"
    echo -e ""

    read -p "    Are you sure you want to proceed? (y/N): " response
    echo -e ""

    case "$response" in
        [yY][eE][sS]|[yY])
            echo -e "${GREEN}[+] Proceeding with guest shutdown...${NOCOLOR}"
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


# How many guests to stop at once (override with ONBOOT_PARALLEL=N).
MAX_PARALLEL="${ONBOOT_PARALLEL:-8}"

# Abort cleanly on Ctrl+C: kill in-flight shutdowns and their pct/qm children.
trap 'trap - INT TERM; echo -e "\n${RED}[!] Interrupted — aborting and killing in-flight operations...${NOCOLOR}"; kill_workers; exit 130' INT TERM

# Worker run in a background job by run_parallel. Emits exactly one line so
# concurrent output never interleaves mid-line. Args: <type> <vmid> <name>
stop_worker() {
    local label="${CYAN}$3 ${BLUE}(${1^^} $2)${NOCOLOR}"
    local t0; t0=$(now_ms)
    stop_guest "$1" "$2" >/dev/null 2>&1; local rc=$?
    local dt; dt=$(fmt_elapsed "$t0" "$(now_ms)")
    if [ "$rc" -eq 0 ]; then
        echo -e "${GREEN}✔ Stopped: $label ${CYAN}(${dt}s)${NOCOLOR}"
    else
        echo -e "${RED}✘ Failed: $label ${CYAN}(${dt}s)${NOCOLOR}"
    fi
}

# --- Phase 1: classify (fast, ordered) -------------------------------------
# Print already-stopped/skipped guests immediately; queue the rest to stop.
TODO=()
while IFS=$'\t' read -r type vmid status onboot template name; do
    label="${CYAN}$name ${BLUE}(${type^^} $vmid)${NOCOLOR}"

    # Templates never run — nothing to do
    [ "$template" = "1" ] && continue

    if [ "$status" != "running" ]; then
        # Only mention on-boot guests that are already down; others are noise
        if [ "$onboot" = "1" ]; then
            echo -e "${GREEN}✔ Already stopped: $label"
        fi
        continue
    fi

    # Running but not an on-boot guest — leave it alone, just flag it
    if [ "$onboot" != "1" ]; then
        echo -e "${YELLOW}⊘ Skipping (running, not on-boot): $label"
        continue
    fi

    TODO+=("$type"$'\t'"$vmid"$'\t'"$name")
done < <(enumerate_guests)

# --- Phase 2: stop queued guests in parallel -------------------------------
echo -e ""
if [ "${#TODO[@]}" -eq 0 ]; then
    echo -e "${CYAN}[*] No on-boot guests need stopping.${NOCOLOR}"
else
    echo -e "${CYAN}[*] Stopping ${#TODO[@]} guest(s), up to ${MAX_PARALLEL} at a time...${NOCOLOR}"
    echo -e ""
    phase_t0=$(now_ms)
    run_parallel "$MAX_PARALLEL" stop_worker < <(printf '%s\n' "${TODO[@]}")
    echo -e ""
    echo -e "${CYAN}[*] Total time: (${PURPLE}$(fmt_elapsed "$phase_t0" "$(now_ms)")s${CYAN})${NOCOLOR}"
fi
echo -e ""

echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e "${GREEN}[✓] Finished processing all on-boot guests!${NOCOLOR}"
echo -e "${BLUE}----------------------------------------------------------------------${NOCOLOR}"
echo -e ""
