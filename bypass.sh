#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

success() {
	echo -e "${GRN}✓ $1${NC}"
}

info() {
	echo -e "${BLU}ℹ $1${NC}"
}

validate_username() {
	local username="$1"
	if [ -z "$username" ]; then echo "Username cannot be empty"; return 1; fi
	if [ ${#username} -gt 31 ]; then echo "Username too long (max 31 characters)"; return 1; fi
	if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then echo "Invalid characters"; return 1; fi
	if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then echo "Must start with letter or underscore"; return 1; fi
	return 0
}

validate_password() {
	local password="$1"
	if [ -z "$password" ]; then echo "Password cannot be empty"; return 1; fi
	if [ ${#password} -lt 4 ]; then echo "Password too short"; return 1; fi
	return 0
}

check_user_exists() {
	local dscl_path="$1"
	local username="$2"
	if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" 2>/dev/null; then
		return 0
	else
		return 1
	fi
}

find_available_uid() {
	local dscl_path="$1"
	local uid=501
	while [ $uid -lt 600 ]; do
		if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
			echo $uid
			return 0
		fi
		uid=$((uid + 1))
	done
	echo "501"
	return 1
}

detect_volumes() {
	local system_vol=""
	local data_vol=""

	info "Detecting system volumes..." >&2

	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
		info "Found data volume: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
		info "Found data volume: $data_vol" >&2
	else
		for vol in /Volumes/*Data; do
			if [ -d "$vol" ]; then
				data_vol=$(basename "$vol")
				warn "Found data volume: $data_vol" >&2
				break
			fi
		done
	fi

	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume."
	fi

	echo "$system_vol|$data_vol"
}

# ─── Detectar volúmenes ───────────────────────────────────────────────────────
volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bypass MDM By Assaf Dori (assafdori.com)   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

# ─── Valores automáticos ──────────────────────────────────────────────────────
realName="user"
username="user"
passw="1234"

echo -e "${YEL}═══════════════════════════════════════${NC}"
echo -e "${YEL}  Starting MDM Bypass Process (Auto)${NC}"
echo -e "${YEL}═══════════════════════════════════════${NC}"
echo ""
info "Usando valores automáticos → Fullname: $realName | Username: $username | Password: $passw"
echo ""

# ─── Renombrar volumen de datos si es necesario ───────────────────────────────
if [ "$data_volume" != "Data" ]; then
	info "Renaming data volume to 'Data' for consistency..."
	if diskutil rename "$data_volume" "Data" 2>/dev/null; then
		success "Data volume renamed successfully"
		data_volume="Data"
	else
		warn "Could not rename data volume, continuing with: $data_volume"
	fi
fi

# ─── Validar rutas ────────────────────────────────────────────────────────────
info "Validating system paths..."

system_path="/Volumes/$system_volume"
data_path="/Volumes/$data_volume"

[ ! -d "$system_path" ] && error_exit "System volume path does not exist: $system_path"
[ ! -d "$data_path" ]   && error_exit "Data volume path does not exist: $data_path"

dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
[ ! -d "$dscl_path" ] && error_exit "Directory Services path does not exist: $dscl_path"

success "All system paths validated"
echo ""

# ─── Crear usuario ────────────────────────────────────────────────────────────
echo -e "${CYAN}Creating Temporary Admin User${NC}"

info "Checking for available UID..."
available_uid=$(find_available_uid "$dscl_path")
success "Using UID: $available_uid"
echo ""

info "Creating user account: $username"

if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null; then
	error_exit "Failed to create user account"
fi

dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"         || warn "Failed to set user shell"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"         || warn "Failed to set real name"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid"    || warn "Failed to set UID"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"          || warn "Failed to set GID"

user_home="$data_path/Users/$username"
if [ ! -d "$user_home" ]; then
	mkdir -p "$user_home" 2>/dev/null && success "Created user home directory" || error_exit "Failed to create user home directory: $user_home"
else
	warn "User home directory already exists: $user_home"
fi

dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "Failed to set home directory"

dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null || error_exit "Failed to set user password"

dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || error_exit "Failed to add user to admin group"

success "User account created successfully"
echo ""

# ─── Bloquear dominios MDM ────────────────────────────────────────────────────
info "Blocking MDM enrollment domains..."

hosts_file="$system_path/etc/hosts"
if [ ! -f "$hosts_file" ]; then
	warn "Hosts file does not exist, creating it"
	touch "$hosts_file" || error_exit "Failed to create hosts file"
fi

grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >> "$hosts_file"
grep -q "mdmenrollment.apple.com"    "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com"    >> "$hosts_file"
grep -q "iprofiles.apple.com"        "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com"        >> "$hosts_file"

success "MDM domains blocked in hosts file"
echo ""

# ─── Configurar bypass MDM ────────────────────────────────────────────────────
info "Configuring MDM bypass settings..."

config_path="$system_path/var/db/ConfigurationProfiles/Settings"

[ ! -d "$config_path" ] && mkdir -p "$config_path" 2>/dev/null && success "Created configuration directory" || warn "Could not create configuration directory"

touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null              && success "Marked setup as complete"         || warn "Could not mark setup as complete"
rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null          && success "Removed activation record"        || info "No activation record to remove"
rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null                  && success "Removed cloud config record"      || info "No cloud config record to remove"
touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null              && success "Created profile installed marker" || warn "Could not create profile marker"
touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null                && success "Created record not found marker"  || warn "Could not create not found marker"

echo ""
echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       MDM Bypass Completed Successfully!     ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Reiniciando en 5 segundos...${NC}"
sleep 5
reboot
