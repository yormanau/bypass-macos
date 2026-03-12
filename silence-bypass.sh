#!/bin/bash

error_exit() { exit 1; }

find_available_uid() {
	local dscl_path="$1"
	local uid=501
	while [ $uid -lt 600 ]; do
		if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
			echo $uid; return 0
		fi
		uid=$((uid + 1))
	done
	echo "501"
}

detect_volumes() {
	local system_vol="" data_vol=""
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"; break
			fi
		fi
	done
	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do [ -d "$vol/System" ] && system_vol=$(basename "$vol") && break; done
	fi
	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
	else
		for vol in /Volumes/*Data; do [ -d "$vol" ] && data_vol=$(basename "$vol") && break; done
	fi
	[ -z "$system_vol" ] && error_exit
	[ -z "$data_vol" ]   && error_exit
	echo "$system_vol|$data_vol"
}

volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

realName="user"
username="user"
passw="1234"

if [ "$data_volume" != "Data" ]; then
	diskutil rename "$data_volume" "Data" 2>/dev/null && data_volume="Data"
fi

system_path="/Volumes/$system_volume"
data_path="/Volumes/$data_volume"

[ ! -d "$system_path" ] && error_exit
[ ! -d "$data_path" ]   && error_exit

dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
[ ! -d "$dscl_path" ] && error_exit

available_uid=$(find_available_uid "$dscl_path")

dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null            || error_exit
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"   2>/dev/null
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"   2>/dev/null
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" 2>/dev/null
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"    2>/dev/null
mkdir -p "$data_path/Users/$username" 2>/dev/null
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" 2>/dev/null
dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null   || error_exit
dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || error_exit

hosts_file="$system_path/etc/hosts"
[ ! -f "$hosts_file" ] && touch "$hosts_file"
grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >> "$hosts_file"
grep -q "mdmenrollment.apple.com"    "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com"    >> "$hosts_file"
grep -q "iprofiles.apple.com"        "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com"        >> "$hosts_file"

config_path="$system_path/var/db/ConfigurationProfiles/Settings"
mkdir -p "$config_path" 2>/dev/null
touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null
rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null
rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null
touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null
touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null

echo "Reiniciando..."
sleep 3
reboot
