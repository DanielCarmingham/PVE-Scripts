#!/bin/bash

# Get a list of all block devices (which includes hard drives)
drives=$(lsblk -d -o NAME | grep -v 'loop' | grep -v 'sr')

# Iterate over each drive
for drive in $drives; do
    echo "Checking SMART status for /dev/$drive:"
    smartctl -a /dev/$drive | grep -E 'Temperature|Model'
    echo "----------------------------------------"
done

