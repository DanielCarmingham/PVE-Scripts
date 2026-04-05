#!/bin/bash

# ## initialization ##

version=2025.11.20
args=("$@")  # SWE MAGA = Make Args Great Again !
this_script="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
show_usage=false

# ## show header ##

echo
echo -e "\033[34m\033[1mRun a Shell Script on an LXC container \033[0m (v$version)"
echo

# ## CLI parameter validation ##

# - Validate Param 1 - container id
if [ "$1" = "" ]; then
	show_usage=true
 	echo "ERROR: No container id value passed on CLI"
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
		show_usage=true
	 	echo "ERROR: Container ID passed doesn't exist (value passed: $1)"
	fi
fi
container_id="$1"

# - Validate Param 2 - bash script file name
if [ "$2" = "" ]; then
	show_usage=true;
 	echo "ERROR: No script value passed on CLI"
else
	# - Validate that script file exists
	if [ ! -f $script_name ]; then
		show_usage=true;
	 	echo "ERROR: Script name passed doesn't exist (value passed: $script_name)"
	fi
fi
script_name="$2"


# - Show usage and bail if we had errors.
if [ "$show_usage" = "true" ]; then
	echo
	echo "Usage: $0 <container-id> <bash-script> <optional-script-parameters> . . <up to 5 parameters>"
	echo
	exit;
fi

# ## Push the script and run it

remote_script_name="${this_script}__$script_name"
remote_script_path="/var/tmp/$remote_script_name"

echo "Remote script path: $remote_script_path"

echo "* Running $script_name on $lxc_name ($lxc_vmid)"
pct push "$lxc_vmid" "$script_name" "$remote_script_path"
pct exec "$lxc_vmid" -- bash -c "chmod u+x $remote_script_path"
pct exec "$lxc_vmid" -- bash -c "$remote_script_path $3 $4 $5 $6 $7"
pct exec "$lxc_vmid" -- bash -c "rm $remote_script_path"

echo "Done..."
echo
