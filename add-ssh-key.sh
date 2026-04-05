#!/bin/bash

# Usage: ./add_ssh_key.sh "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQE..."

AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
SSH_DIR="$HOME/.ssh"

# Ensure an SSH key is provided
if [ -z "$1" ]; then
    echo "Usage: $0 \"<SSH_PUBLIC_KEY>\""
    exit 1
fi

echo
echo "CLI PARMS:"
echo "0 = $0"
echo "1 = $1"
echo "2 = $2"
echo "3 = $3"
echo


SSH_KEY="$1"

# Ensure .ssh directory exists
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Ensure authorized_keys file exists
touch "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

# Check if the key is already present
if grep -qF -- "$SSH_KEY" "$AUTHORIZED_KEYS"; then
    echo "Key already exists in authorized_keys."
else
    echo "$SSH_KEY" >> "$AUTHORIZED_KEYS"
    echo "Key added to authorized_keys."
fi
