#!/bin/bash

# ## initialization ##

version=2025.02.08
args=("$@")  # SWE MAGA = Make Args Great Again !
this_script="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
show_usage=false

# ## show header ##

echo
echo -e "\033[34m\033[1mRun a Shell Script on all your LXC containers \033[0m (v$version)"
echo

# ## CLI parameter validation ##

# - if param 1 is empty
if [ "$1" = "" ];
then
	show_usage=true;
 	echo "ERROR: No script value passed on CLI"
fi;

# - if param 1 doesn't end in .sh
# TODO: couldn't get this to work:
#if [[ "$1" =~ *.sh ]];
#then
#	show_usage=true;
# 	echo "ERROR: Script value must end in .sh (value passed: $1)"
#fi;

if [ "$show_usage" = "true" ];
then
	echo
	echo "Usage: $0 <bash-script> <optional-script-parameters> . . <up to 5 parameters>"
	echo
	exit;
fi;

mapfile -t list < <(pct list)

script_name="${args[0]}"
remote_script_name="${this_script}__$script_name"
remote_script_path="/var/tmp/$remote_script_name"

echo "Remote script path: $remote_script_path"

for i in "${list[@]}"
do
	IFS=', ' read -r -a lxc <<< "$i"
        lxc_vmid="${lxc[0]}"
        lxc_status="${lxc[1]}"
	lxc_name="${lxc[2]}"
        if [ "$lxc_vmid" != "VMID" ]; # to skip the headers row
	then
		echo "* Running $script_name on $lxc_name ($lxc_vmid)"
		pct push "$lxc_vmid" "$script_name" "$remote_script_path"
		pct exec "$lxc_vmid" -- bash -c "chmod u+x $remote_script_path"
		pct exec "$lxc_vmid" -- bash -c "$remote_script_path $2 $3 $4 $5 $6"
		pct exec "$lxc_vmid" -- bash -c "rm $remote_script_path"
#		exit; # uncomment to make it test on the first container only
	fi
done

echo "Done..."
echo
