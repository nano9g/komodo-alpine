#!/bin/sh

KOMODO_MAIN_REPO="moghtech/komodo"
KOMODO_ALPINE_REPO="nano9g/komodo-alpine"

KOMODO_DEFAULT_PERIPHERY_SCRIPT_URL="https://raw.githubusercontent.com/${KOMODO_MAIN_REPO}/main/scripts/setup-periphery.py"
KOMODO_DEFAULT_CONFIG_URL="https://raw.githubusercontent.com/${KOMODO_MAIN_REPO}/main/config/periphery.config.toml"

PERIPHERY_EXECUTABLE="periphery"
PERIPHERY_BINARY_PATH="/usr/local/bin/${PERIPHERY_EXECUTABLE}"
PERIPHERY_OPENRC_SERVICE_PATH="/etc/init.d/${PERIPHERY_EXECUTABLE}"
PERIPHERY_CONFIG_DIR="/etc/komodo"
PERIPHERY_CONFIG_PATH="${PERIPHERY_CONFIG_DIR}/periphery.config.toml"
PERIPHERY_ARCHIVE_PREFIX="periphery_musl"  # Will be suffixed with _<architecture>.tar.gz

# Service file content
PERIPHERY_OPENRC_SERVICE=$(cat <<EOF
#!/sbin/openrc-run

description="Komodo Periphery Agent"
command="$PERIPHERY_BINARY_PATH"
command_args="--config-path ${PERIPHERY_CONFIG_PATH}"
command_background=true
required_dirs=${PERIPHERY_CONFIG_DIR}
pidfile=/run/periphery.pid
output_log=/var/log/komodo.log
output_err=/var/log/komodo.err
EOF
)


# Permissions check
if [ "$(id -u)" -ne 0 ]; then printf %s\\n "Please run as root." >&2; exit 1; fi


# Use official installer for other distros
distro=$(cat /etc/*-release | grep -e '^ID' | head -n1 | cut -d '=' -f2)
if [ "$distro" != 'alpine' ]; then
	printf %s\\n "🐧 This is $distro -- running standard Periphery installer"
	curl -sSL "$KOMODO_DEFAULT_PERIPHERY_SCRIPT_URL" | python3
	exit
fi



show_help() {
	printf %s\\n\\n "Usage: setup_periphery.sh [-f] [-p] [-s]  [-c] [-u] [-h]"
	printf %s\\n\\n "Install Komodo Periphery."
	printf %s\\n "	-f Force install (binary and service; will not touch config)"
	printf %s\\n "	-p Force only binary install"
	printf %s\\n "	-s Force only service install"
	printf %s\\n "	-c Overwrite existing config"
	printf %s\\n "	-u Uninstall"
	exit 2
}


# Make sure we don't leave temporary files behind
cleanup() {
	if [ ! -z "$PERIPHERY_TMP_DIR" ] && [ -d "$PERIPHERY_TMP_DIR" ]; then
		rm -rf "$PERIPHERY_TMP_DIR"
	fi
}


# Check to see if binary install/upgrade is needed
# Return code 1 if required, 0 otherwise
local_version_outdated() {
	if [ -f "$PERIPHERY_BINARY_PATH" ]; then
		_force_required_reason=""
		_force_required_action=""
		# Remote tag comes with a "v" prefix, while periphery --version returns "periphery <version>",
		# so we strip both prefixes in order to compare them
		_local_version_result=$($PERIPHERY_BINARY_PATH --version)
		_local_version_number=${_local_version_result#periphery }
		
		if [ "$_local_version_number" = "$remote_version_number" ]; then
			_force_required_reason="☑️ Local Periphery binary is already ${remote_version_number}"
			_force_required_action="reinstall"
		elif  [ "$( { printf %s\\n "$_local_version_number"; printf %s\\n "$remote_version_number"; } | sort -n -t. -k1,1 -k2,2 -k3,3 | tail -n1 )" = "$_local_version_number" ]; then
			# Local version > Remote version
			# Credit: https://gist.github.com/knu/c4db76e3cc596d788edd60dac596432d
			_force_required_reason="🔺 Local Periphery binary is NEWER than remote (${_local_version_number} > ${remote_version_number})"
			_force_required_action="downgrade"
		fi

		if [ "$_force_required_reason" != "" ]; then
			printf %s\\n
			printf %s\\n "$_force_required_reason"
			printf %s\\n "   Rerun with -p to ${_force_required_action} (-f to also reinstall service)"
			printf %s\\n
			return 0
		fi

		printf %s\\n "🔸 Local Periphery is out of date ($_local_version_number)"
	fi
	return 1
}


# Periphery OpenRC service install (just places the file; doesn't start the service)
# Return code 1 if service was updated, 0 otherwise
install_service() {
	_force=$1
	if [ ! -f "$PERIPHERY_OPENRC_SERVICE_PATH" ] || [ "$_force" = "1" ]; then
		# Service wasn't present, or install was forced
		printf %s\\n "🧩 Installing Periphery service to ${PERIPHERY_OPENRC_SERVICE_PATH}"
		printf %s\\n "$PERIPHERY_OPENRC_SERVICE" > "$PERIPHERY_OPENRC_SERVICE_PATH"
		chmod +x "$PERIPHERY_OPENRC_SERVICE_PATH"
		return 1
	else
		# Alert when service file doesn't match expected content
		# (For the diff command, make sure both files end with a newline, then ignore blank lines and whitespace changes)
		periphery_service_diff=$(diff -bB <(cat "$PERIPHERY_OPENRC_SERVICE_PATH"; printf \\n) <(printf %s\\n "$PERIPHERY_OPENRC_SERVICE"))
		diff_result=$?
		if [ "$diff_result" != 0 ]; then
			printf %s\\n
			printf %s\\n "⚠️ Periphery service does not match; run again with -s to force update"
			printf %s\\n "$periphery_service_diff"
			printf %s\\n
		fi
	fi
	return 0
}


# Periphery binary install
# Return code 1 if binary was updated, 0 otherwise
install_binary() {
	_proceed=$1
	if [ "$_proceed" != "1" ]; then
		local_version_outdated
		_proceed=$?
	fi

	if [ "$_proceed" = "1" ]; then
		# Download binary
		mkdir -p $PERIPHERY_TMP_DIR
		tmp_archive_path="${PERIPHERY_TMP_DIR}/${PERIPHERY_ARCHIVE}"
		tmp_binary_path="${PERIPHERY_TMP_DIR}/${PERIPHERY_EXECUTABLE}"
		url="https://github.com/${KOMODO_ALPINE_REPO}/releases/download/${remote_version_tag}/${PERIPHERY_ARCHIVE}"

		printf %s\\n "   Downloading Periphery from ${url}"
		curl -sSLf "$url" -o "$tmp_archive_path"
		result=$?
		if [ "$result" != "0" ]; then
			printf %s\\n "🛑 Download failed"
			cleanup
			exit $result
		fi

		# Extract archive
		tar xf "$tmp_archive_path" -C "$PERIPHERY_TMP_DIR"
		if [ ! -f "$tmp_binary_path" ]; then
			printf %s\\n "🛑 Failed to extract Periphery binary"
			cleanup
			exit 3
		fi

		printf %s\\n "🧩 Installing Periphery to '${PERIPHERY_BINARY_PATH}'"
		# Stop existing service before binary installation (if this is the initial install and it's not present yet, we'll ignore the error)
		service periphery stop 2>/dev/null || true
		# Install binary
		mv "$tmp_binary_path" "$PERIPHERY_BINARY_PATH"
		chmod +x "$PERIPHERY_BINARY_PATH"
		return 1
	fi
	return 0
}


install_config() {
	_force=$1
	# Never overwrite config unless explicitly requested
	if [ -f "$PERIPHERY_CONFIG_PATH" ] && [ "$_force" != "1" ]; then
		return 0
	fi

	printf %s\\n "🧩 Applying default configuration"
	printf %s\\n "   Downloading from ${KOMODO_DEFAULT_CONFIG_URL}"
	printf %s\\n "   to ${PERIPHERY_CONFIG_PATH}"
	curl -sSLf "$KOMODO_DEFAULT_CONFIG_URL" -o "$PERIPHERY_CONFIG_PATH"
	result=$?
	if [ "$result" != "0" ]; then
		printf %s\\n "🛑 Download failed"
		cleanup
		exit $result
	fi
	return 1
}


uninstall() {
	printf %s\\n "🚮 Uninstalling..."
	set -e
	service periphery stop
	rc-update del periphery
	rm "$PERIPHERY_BINARY_PATH"
	rm "$PERIPHERY_OPENRC_SERVICE_PATH"
	exit
}



# Alpine time
printf %s\\n "🏔️ This is Alpine -- using musl Periphery and OpenRC service"


do_service_install=0
do_binary_install=0
overwrite_config=0

# Process arguments
OPTIND=1
while getopts "fchpsu" opt; do
  case "$opt" in
	f)
		printf %s\\n "✴️ Forcing binary and service install (-f)"
		do_binary_install=1
		do_service_install=1
		;;
    c)
		printf %s\\n "⚛️ Overwriting exiting config (-c)"
		overwrite_config=1
		;;
	h)
		show_help
		;;
    p)
		printf %s\\n "✴️ Forcing binary install (-p)"
		do_binary_install=1
      	;;
    s)
		printf %s\\n "✴️ Forcing service install (-s)"
		do_service_install=1
    	;;
    u)
		uninstall
    	;;
	?)
		show_help
		;;
  esac
done
shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift


# Set up Error handling
trap cleanup ERR EXIT

# Translate architecture names as needed
sys_arch=$(uname -m)
case $sys_arch in
	x86_64)
		sys_arch=amd64
		;;
esac


PERIPHERY_ARCHIVE="${PERIPHERY_ARCHIVE_PREFIX}_${sys_arch}.tar.gz"
PERIPHERY_TMP_DIR="/tmp/$(cat /dev/urandom | tr -cd 'a-z0-9' | head -c 10)"

# Find Periphery release info
remote_version_data=$(curl --no-progress-meter "https://api.github.com/repos/${KOMODO_ALPINE_REPO}/releases/latest")
remote_version_tag=$(printf %s "$remote_version_data" | grep '"tag_name":' | grep -Eo 'v[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')
remote_version_number=${remote_version_tag#v}
if [ -z "$remote_version_tag" ]; then
	printf %s\\n "🛑 Failed to find latest Periphery release for Alpine from ${KOMODO_ALPINE_REPO}"
	printf %s\\n "curl output: $remote_version_data"
	exit 100
fi
printf %s\\n "ℹ️ Latest Periphery for Alpine build is ${remote_version_number}"

# Do installs
install_service $do_service_install
service_updated=$?
install_binary $do_binary_install
binary_updated=$?
install_config $overwrite_config
config_updated=$?

# Enable and start service if needed
rc-update show default | grep periphery > /dev/null 2>&1
service_runlevel=$?
service periphery status > /dev/null 2>&1
service_status=$?
if [ "$binary_updated" = "1" ] || [ "$service_updated" = "1" ] || [ "$config_updated" = "1" ] || [ "$service_runlevel" != "0" ] || [ "$service_status" != "0" ]; then
	printf %s\\n "▶️ Finishing up"
	rc-update add periphery default
	service periphery restart
fi

# Clean up temp files
cleanup
