#!/bin/bash
# ==============================================================================
# onboot_lib.sh — shared helpers for the on-boot guest manager scripts
#
# Enumerates Proxmox guests (LXC containers + QEMU VMs) by reading their config
# files directly. That is far faster than forking `pct config` / `qm config`
# once per guest — those are Perl and cost ~0.5s each to start up.
# ==============================================================================

# Parse onboot, template and name from the *main* section of a guest config
# file. Snapshot sections (lines beginning with "[") are ignored.
# Usage: _parse_conf <conf_file> <name_key>   ->  "<onboot>\t<template>\t<name>"
_parse_conf() {
    awk -v namekey="$2:" '
        /^\[/         { exit }                 # stop at first snapshot section
        /^onboot:/    { ob  = $2 }
        /^template:/  { tpl = $2 }
        $1 == namekey { nm  = $2 }
        END { printf "%s\t%s\t%s", (ob ? ob : 0), (tpl ? tpl : 0), nm }
    ' "$1" 2>/dev/null
}

# Emit one tab-separated record per guest on the local node:
#   <type>\t<vmid>\t<status>\t<onboot>\t<template>\t<name>
# where <type> is "ct" or "vm".
enumerate_guests() {
    local vmid status listname name onboot template

    # --- LXC containers ---------------------------------------------------
    while read -r vmid status _; do
        [ "$vmid" = "VMID" ] && continue
        IFS=$'\t' read -r onboot template name \
            < <(_parse_conf "/etc/pve/lxc/$vmid.conf" hostname)
        printf 'ct\t%s\t%s\t%s\t%s\t%s\n' \
            "$vmid" "$status" "$onboot" "$template" "${name:-$vmid}"
    done < <(pct list)

    # --- QEMU virtual machines -------------------------------------------
    # `qm list` columns: VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID
    while read -r vmid listname status _; do
        [ "$vmid" = "VMID" ] && continue
        IFS=$'\t' read -r onboot template name \
            < <(_parse_conf "/etc/pve/qemu-server/$vmid.conf" name)
        printf 'vm\t%s\t%s\t%s\t%s\t%s\n' \
            "$vmid" "$status" "$onboot" "$template" "${name:-$listname}"
    done < <(qm list)
}

# Start a guest by type. Reads from /dev/null so it never blocks on stdin.
start_guest() {
    case "$1" in
        ct) pct start "$2" </dev/null ;;
        vm) qm  start "$2" </dev/null ;;
    esac
}

# Gracefully shut a guest down, forcing a hard stop after the timeout elapses.
stop_guest() {
    case "$1" in
        ct) pct shutdown "$2" -timeout 60 -forceStop 1 </dev/null ;;
        vm) qm  shutdown "$2" -timeout 60 -forceStop 1 </dev/null ;;
    esac
}

# Run a worker function over a set of guests with bounded concurrency.
#   run_parallel <max_jobs> <worker_fn>   (reads work items from stdin)
# Each stdin line is a tab-separated record; <worker_fn> is invoked with that
# line's fields as positional arguments and runs in its own background job.
# No more than <max_jobs> workers run at once. Workers should emit a single
# line of output so concurrent writes don't interleave mid-line.
run_parallel() {
    local max=$1 worker=$2
    local running=0
    local -a fields
    while IFS=$'\t' read -r -a fields; do
        [ ${#fields[@]} -eq 0 ] && continue
        "$worker" "${fields[@]}" &
        running=$((running + 1))
        if (( running >= max )); then
            wait -n
            running=$((running - 1))
        fi
    done
    wait
}

# Current time in integer milliseconds (locale-independent — avoids the
# decimal-separator pitfalls of $EPOCHREALTIME).
now_ms() { date +%s%3N; }

# Format an elapsed span (two now_ms values) as seconds to one decimal place,
# rounded to the nearest tenth.  fmt_elapsed <start_ms> <end_ms>  ->  "12.4"
fmt_elapsed() {
    local tenths=$(( ($2 - $1 + 50) / 100 ))
    printf '%d.%d' $(( tenths / 10 )) $(( tenths % 10 ))
}

# Terminate every running background worker and the pct/qm processes they
# spawned. Meant to be called from a SIGINT/SIGTERM trap in the entry script.
kill_workers() {
    local p
    for p in $(jobs -p); do
        pkill -TERM -P "$p" 2>/dev/null   # the pct/qm child under the worker
        kill   -TERM "$p"   2>/dev/null   # the worker subshell itself
    done
}
