#!/bin/bash

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

warn() {
	echo -e "${YEL}ADVERTENCIA: $1${NC}"
}

success() {
	echo -e "${GRN}✓ $1${NC}"
}

info() {
	echo -e "${BLU}ℹ $1${NC}"
}

validate_username() {
	local username="$1"
	if [ -z "$username" ]; then echo "El nombre de usuario no puede estar vacío"; return 1; fi
	if [ ${#username} -gt 31 ]; then echo "Nombre de usuario muy largo (máximo 31 caracteres)"; return 1; fi
	if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then echo "El usuario solo puede contener letras, números, guión y guión bajo"; return 1; fi
	if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then echo "El usuario debe comenzar con una letra o guión bajo"; return 1; fi
	return 0
}

validate_password() {
	local password="$1"
	if [ -z "$password" ]; then echo "La contraseña no puede estar vacía"; return 1; fi
	if [ ${#password} -lt 4 ]; then echo "Contraseña muy corta (mínimo 4 caracteres)"; return 1; fi
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

	info "Detectando volúmenes del sistema..." >&2

	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Volumen del sistema encontrado: $system_vol" >&2
				break
			fi
		fi
	done

	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Usando volumen con directorio /System: $system_vol" >&2
				break
			fi
		done
	fi

	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
		info "Volumen de datos encontrado: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
		info "Volumen de datos encontrado: $data_vol" >&2
	else
		for vol in /Volumes/*Data; do
			if [ -d "$vol" ]; then
				data_vol=$(basename "$vol")
				warn "Volumen de datos encontrado: $data_vol" >&2
				break
			fi
		done
	fi

	if [ -z "$system_vol" ]; then
		error_exit "No se pudo detectar el volumen del sistema. Asegúrate de estar en modo Recuperación con macOS instalado."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "No se pudo detectar el volumen de datos. Asegúrate de estar en modo Recuperación con macOS instalado."
	fi

	echo "$system_vol|$data_vol"
}

volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Bypass MDM By Yorman Aular           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "Volumen del sistema: $system_volume"
success "Volumen de datos: $data_volume"
echo ""

PS3='Elige una opción: '
options=("Bypass MDM desde Recuperación" "Eliminar contraseña de usuario" "Reiniciar y salir")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM desde Recuperación")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Iniciando proceso de Bypass MDM${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		if [ "$data_volume" != "Data" ]; then
			info "Renombrando volumen de datos a 'Data'..."
			if diskutil rename "$data_volume" "Data" 2>/dev/null; then
				success "Volumen de datos renombrado correctamente"
				data_volume="Data"
			else
				warn "No se pudo renombrar el volumen de datos, continuando con: $data_volume"
			fi
		fi

		info "Validando rutas del sistema..."

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		if [ ! -d "$system_path" ]; then error_exit "La ruta del volumen del sistema no existe: $system_path"; fi
		if [ ! -d "$data_path" ]; then error_exit "La ruta del volumen de datos no existe: $data_path"; fi

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
		if [ ! -d "$dscl_path" ]; then error_exit "La ruta de Servicios de Directorio no existe: $dscl_path"; fi

		success "Todas las rutas del sistema validadas"
		echo ""

		echo -e "${CYAN}Creando usuario administrador temporal${NC}"
		echo -e "${NC}Presiona Enter para usar los valores por defecto (recomendado)${NC}"

		read -p "Ingresa el nombre completo (Por defecto 'Apple'): " realName
		realName="${realName:=Apple}"

		while true; do
			read -p "Ingresa el nombre de usuario (Por defecto 'Apple'): " username
			username="${username:=Apple}"
			if validation_msg=$(validate_username "$username"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Intenta de nuevo o presiona Ctrl+C para salir${NC}"
			fi
		done

		if check_user_exists "$dscl_path" "$username"; then
			warn "El usuario '$username' ya existe en el sistema"
			read -p "¿Deseas usar un nombre de usuario diferente? (s/n): " response
			if [[ "$response" =~ ^[Ss]$ ]]; then
				while true; do
					read -p "Ingresa un nombre de usuario diferente: " username
					if [ -z "$username" ]; then warn "El nombre de usuario no puede estar vacío"; continue; fi
					if validation_msg=$(validate_username "$username"); then
						if ! check_user_exists "$dscl_path" "$username"; then break
						else warn "El usuario '$username' también existe. Prueba otro nombre."; fi
					else warn "$validation_msg"; fi
				done
			else
				warn "Continuando con el usuario existente '$username' (puede causar conflictos)"
			fi
		fi

		while true; do
			read -p "Ingresa la contraseña temporal (Por defecto '1234'): " passw
			passw="${passw:=1234}"
			if validation_msg=$(validate_password "$passw"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Intenta de nuevo o presiona Ctrl+C para salir${NC}"
			fi
		done

		echo ""

		info "Buscando UID disponible..."
		available_uid=$(find_available_uid "$dscl_path")
		if [ $? -eq 0 ] && [ "$available_uid" != "501" ]; then
			info "El UID 501 está en uso, usando UID $available_uid"
		else
			available_uid="501"
		fi
		success "Usando UID: $available_uid"
		echo ""

		info "Creando cuenta de usuario: $username"

		if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null; then
			error_exit "No se pudo crear la cuenta de usuario"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" || warn "No se pudo establecer el shell del usuario"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" || warn "No se pudo establecer el nombre real"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" || warn "No se pudo establecer el UID"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" || warn "No se pudo establecer el GID"

		user_home="$data_path/Users/$username"
		if [ ! -d "$user_home" ]; then
			if mkdir -p "$user_home" 2>/dev/null; then
				success "Directorio home del usuario creado"
			else
				error_exit "No se pudo crear el directorio home: $user_home"
			fi
		else
			warn "El directorio home del usuario ya existe: $user_home"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "No se pudo establecer el directorio home"

		if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null; then
			error_exit "No se pudo establecer la contraseña del usuario"
		fi

		if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null; then
			error_exit "No se pudo agregar el usuario al grupo de administradores"
		fi

		success "Cuenta de usuario creada correctamente"
		echo ""

		info "Bloqueando dominios de inscripción MDM..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "El archivo hosts no existe, creándolo..."
			touch "$hosts_file" || error_exit "No se pudo crear el archivo hosts"
		fi

		grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
		grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >>"$hosts_file"
		grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >>"$hosts_file"

		success "Dominios MDM bloqueados en el archivo hosts"
		echo ""

		info "Configurando ajustes de bypass MDM..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"

		if [ ! -d "$config_path" ]; then
			if mkdir -p "$config_path" 2>/dev/null; then
				success "Directorio de configuración creado"
			else
				warn "No se pudo crear el directorio de configuración"
			fi
		fi

		touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null && success "Configuración inicial marcada como completada" || warn "No se pudo marcar la configuración como completada"
		rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null && success "Registro de activación eliminado" || info "No había registro de activación"
		rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null && success "Registro de configuración en la nube eliminado" || info "No había registro de configuración en la nube"
		touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Marcador de perfil instalado creado" || warn "No se pudo crear el marcador de perfil"
		touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Marcador de registro no encontrado creado" || warn "No se pudo crear el marcador"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       ¡Bypass MDM completado con éxito!      ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		defaults write "$data_path/Library/Preferences/.GlobalPreferences" AppleLanguages -array "es-CO"
		defaults write "$data_path/Library/Preferences/.GlobalPreferences" AppleLocale -string "es_CO"
		defaults write "$data_path/Library/Preferences/.GlobalPreferences" AppleCollationOrder -string "es"
		echo -e "${CYAN}Reiniciando en 5 segundos...${NC}"
		sleep 5
		reboot
		break
		;;

	"Eliminar contraseña de usuario")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Eliminar contraseña de usuario${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"
		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"

		if [ ! -d "$dscl_path" ]; then
			error_exit "No se encontró la base de datos de usuarios. Asegúrate de estar en modo Recuperación."
		fi

		info "Usuarios disponibles en el sistema:"
		echo ""

		# Listar usuarios reales (UID >= 501)
		mapfile -t user_list < <(dscl -f "$dscl_path" localhost -list /Local/Default/Users UniqueID 2>/dev/null | awk '$2 >= 501 {print $1}')

		if [ ${#user_list[@]} -eq 0 ]; then
			error_exit "No se encontraron usuarios en el sistema."
		fi

		for i in "${!user_list[@]}"; do
			echo -e "  ${CYAN}$((i+1))${NC}) ${user_list[$i]}"
		done

		echo ""
		read -p "Ingresa el número del usuario: " user_index
		user_index=$((user_index - 1))

		if [ $user_index -lt 0 ] || [ $user_index -ge ${#user_list[@]} ]; then
			error_exit "Opción inválida."
		fi

		target_user="${user_list[$user_index]}"
		info "Usuario seleccionado: $target_user"
		echo ""

		if dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$target_user" "" 2>/dev/null; then
			success "Contraseña eliminada correctamente para el usuario: $target_user"
		else
			error_exit "No se pudo eliminar la contraseña del usuario: $target_user"
		fi

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║     ¡Contraseña eliminada con éxito!         ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Reiniciando en 5 segundos...${NC}"
		sleep 5
		reboot
		break
		;;

	"Reiniciar y salir")
		echo ""
		info "Reiniciando el sistema..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Opción inválida: $REPLY${NC}"
		;;
	esac
done
