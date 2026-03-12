#!/bin/bash

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
warn()        { echo -e "${YEL}ADVERTENCIA: $1${NC}"; }
success()     { echo -e "${GRN}✓ $1${NC}"; }
info()        { echo -e "${BLU}ℹ $1${NC}"; }

# Detectar volumen de datos
data_path=""
if [ -d "/Volumes/Data" ]; then
	data_path="/Volumes/Data"
else
	for vol in /Volumes/*Data; do
		[ -d "$vol" ] && data_path="$vol" && break
	done
fi

[ -z "$data_path" ] && error_exit "No se pudo detectar el volumen de datos."

dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
[ ! -d "$dscl_path" ] && error_exit "No se encontró la base de datos de usuarios."

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Cambiar contraseña de usuario         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Listar usuarios reales (UID >= 501) compatible con bash 3
info "Usuarios disponibles:"
echo ""

user_list=()
while IFS= read -r line; do
	user_list+=("$line")
done < <(dscl -f "$dscl_path" localhost -list /Local/Default/Users UniqueID 2>/dev/null | awk '$2 >= 501 {print $1}')

[ ${#user_list[@]} -eq 0 ] && error_exit "No se encontraron usuarios en el sistema."

for i in "${!user_list[@]}"; do
	echo -e "  ${CYAN}$((i+1))${NC}) ${user_list[$i]}"
done

echo ""
read -p "Elige el número del usuario: " user_index
user_index=$((user_index - 1))

if [ $user_index -lt 0 ] || [ $user_index -ge ${#user_list[@]} ]; then
	error_exit "Opción inválida."
fi

target_user="${user_list[$user_index]}"
info "Usuario seleccionado: $target_user"
echo ""

read -p "Ingresa la nueva contraseña: " new_pass
echo ""

[ -z "$new_pass" ] && error_exit "La contraseña no puede estar vacía."
[ ${#new_pass} -lt 4 ] && error_exit "La contraseña debe tener al menos 4 caracteres."

if dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$target_user" "$new_pass" 2>/dev/null; then
	echo ""
	echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
	echo -e "${GRN}║     ¡Contraseña cambiada con éxito!          ║${NC}"
	echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
	echo ""
	success "Usuario: $target_user"
	success "Nueva contraseña: $new_pass"
	echo ""
	echo -e "${CYAN}Reiniciando en 5 segundos...${NC}"
	sleep 5
	reboot
else
	error_exit "No se pudo cambiar la contraseña del usuario: $target_user"
fi
