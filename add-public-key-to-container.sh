#!/bin/bash

# ## initialization ##

version=2025.11.20
public_key_file="$HOME/.ssh/id_rsa.pub"  #default key file
min_key_length=50

# ## show header ##

echo
echo -e "\033[34m\033[1mAdd SSH public key to the specified LXC container \033[0m (v$version)"
echo
echo "This will add a public key to the authorized_keys."
echo
echo "Usage:  $0 <container-id> [<optional-public-key-file>]"
echo

# ## validate CLI params ##

# - Validate Param 1 - container id
if [ "$1" = "" ]; then
        echo "ERROR: No container id value passed on CLI"
	echo
	exit;
else
        # - Validate container ID is valid
        mapfile -t list < <(pct list)
        for i in "${list[@]}"; do
                IFS=', ' read -r -a lxc <<< "$i"
                lxc_vmid="${lxc[0]}"
                lxc_status="${lxc[1]}"
                lxc_name="${lxc[2]}"
                if [[ "$lxc_vmid" == "$1" ]]; then
                        found=true
                        break
                fi
        done
        if [ ! $found ];
        then
                echo "ERROR: Container ID passed doesn't exist (value passed: $1)"
		echo
		exit;
        fi
fi
container_id="$1"

# - Validate Param 2 - public key file
if [[ "$2" == "" ]];
then
	echo "No key file specified, using default: $public_key_file"
	echo
else
	public_key_file="$2"
	echo "Using public key file passed on command line: $public_key_file"
	echo
fi

# ## check dependencies ##

if [ ! -f "$public_key_file" ];
then
	echo "ERROR: File not found!  $public_key_file"
	echo
	exit;
fi

read -r public_key<"$public_key_file"

public_key_length=${#public_key}

if [[ public_key_length -lt min_key_length ]];
then
	echo "ERROR: Key must be first line of file $public_key_file and must be longer than $min_key_length chars"
	echo
	exit;
fi

if [ ! -f "run-shell-script-on-container.sh" ];
then
	echo "ERROR: Dependency not found: run-shell-script-on-container.sh"
	echo
	exit;
fi

if [ ! -f "add-ssh-key.sh" ];
then
	echo "ERROR: Dependency not found: add-ssh-key.sh"
	echo
	exit;
fi


# ## get confirmation ##

read -p "Are you sure? (yn)" -n 1 -r
echo    # (optional) move to a new line
if [[ ! "$REPLY" =~ ^[Yy]$ ]]
then
	echo "Aborted..."
	echo
	exit;
fi

# ## do it! ##

source run-shell-script-on-container.sh "$container_id" "add-ssh-key.sh" "'$public_key'"
