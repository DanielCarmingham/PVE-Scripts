#!/bin/bash

# Get a list of all LXC container IDs
lxc_ids=$(pct list | awk 'NR>1 {print $1}')

echo "LXC Container VLAN Settings:"
echo "---------------------------"

# Iterate through each LXC container
for lxc_id in $lxc_ids; do
    echo "Container ID: $lxc_id"
    
    # Get the path to the container's configuration file
    config_file="/etc/pve/lxc/$lxc_id.conf"

    # Check if the config file exists
    if [ -f "$config_file" ]; then
        # Extract network interface lines and check for VLAN tags
        vlan_settings=$(grep -E '^net[0-9]+:' "$config_file" | grep 'tag=')
        
        if [ -n "$vlan_settings" ]; then
            echo "$vlan_settings"
        else
            echo "No explicit VLAN tag found for network interfaces."
        fi
    else
        echo "Configuration file not found: $config_file"
    fi
    echo "" # Add a blank line for readability
done
