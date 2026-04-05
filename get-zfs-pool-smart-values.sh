#!/bin/bash

# Define the pool name and output file
POOL_NAME="zfs1" # Replace with your actual ZFS pool name
OUTPUT_FILE="smartctl_output_${POOL_NAME}.txt"

# Ensure the script is run with root privileges for smartctl
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo"
   exit 1
fi

# Clear the output file if it exists, start fresh
> "$OUTPUT_FILE"

echo "Starting smartctl check for pool: $POOL_NAME" | tee -a "$OUTPUT_FILE"
echo "--------------------------------------------------" | tee -a "$OUTPUT_FILE"

# Get the list of devices in the ZFS pool using 'zpool status -P'
# The -P option ensures full device paths are displayed (e.g., /dev/sda instead of sda)
# We parse the output to extract device names, skipping main pool name, raid levels, etc.
# This assumes a standard ZFS pool structure (e.g., poolname -> raidz1-0/mirror-0 -> device)
DEVICES=$(zpool status -P "$POOL_NAME" | grep -E '^\s*(/dev/|ata-|nvme-)' | awk '{print $1}')

# Iterate over each device found
for device in $DEVICES; do
    # Zpool status might list partitions (e.g., /dev/sda1), but smartctl needs the whole disk (e.g., /dev/sda).
    # We need to resolve the full disk path from a partition or a /dev/disk/by-id link.

    # Resolve to the actual block device path if it's a by-id link
    if [[ -L "$device" ]]; then
        # readlink -f gets the canonical path
        full_device_path=$(readlink -f "$device")
    else
        full_device_path="$device"
    fi

    # smartctl usually works on whole disks, not partitions.
    # We can try to extract the main device name (e.g., /dev/sda from /dev/sda1)
    if [[ "$full_device_path" =~ nvme ]]; then
      # NVMe devices use a different naming scheme (e.g., /dev/nvme0n1)
      # smartctl works with these directly
      disk_path="$full_device_path"
    elif [[ "$full_device_path" =~ ^/dev/[hs]d[a-z]+[0-9]* ]]; then
      # For SATA/SCSI, strip potential partition numbers
      disk_path=$(echo "$full_device_path" | sed 's/[0-9]*$//')
    else
      # Fallback for other potential naming schemes
      disk_path="$full_device_path"
    fi

    echo "--- Running smartctl on $disk_path ---" | tee -a "$OUTPUT_FILE"
    # Run smartctl and append output to the file
    if smartctl -a "$disk_path" >> "$OUTPUT_FILE" 2>&1; then
        echo "--- smartctl succeeded for $disk_path ---" | tee -a "$OUTPUT_FILE"
    else
        echo "--- smartctl failed for $disk_path (check output above for errors) ---" | tee -a "$OUTPUT_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"
done

echo "--------------------------------------------------" | tee -a "$OUTPUT_FILE"
echo "smartctl checks completed. Output appended to $OUTPUT_FILE"
