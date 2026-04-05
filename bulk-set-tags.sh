#!/bin/bash

# For Virtual Machines (VMs)
#for VMID in 101 102 103; do
#  qm set $VMID --tags "newtag1,newtag2"
#done

# For LXC Containers
for CTID in 131 127 ; do
  pct set $CTID --tags "app"
done
