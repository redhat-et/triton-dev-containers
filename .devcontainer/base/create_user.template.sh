#! /bin/bash -e

trap "echo -e '\nScript interrupted. Exiting gracefully.'; exit 1" SIGINT

# Copyright (C) 2024-2025 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
	cat <<EOF >&2
Usage: $0
   -u | --user <username>
   -G | --group <group_name>
   -g | --gid <usergid>
   -i | --id <userid>
EOF
	exit 1
}

install_sudo() {
	echo "Installing and configuring sudo for $USERNAME ..."
	dnf -y install sudo
	tee /etc/sudoers.d/"$USERNAME" <<EOF
# Enable the user account to run sudo without a password
$USERNAME ALL=(root) NOPASSWD:ALL
EOF
	chmod 0440 /etc/sudoers.d/"$USERNAME"
}

# Function to update MAX_UID and MAX_GID in /etc/login.defs
update_max_uid_gid() {
	local current_max_uid
	local current_max_gid
	local current_min_uid
	local current_min_gid

	echo "Updating max UID and GID ..."

	# Get current max UID and GID from /etc/login.defs
	current_max_uid=$(grep "^UID_MAX" /etc/login.defs | awk '{print $2}')
	current_max_gid=$(grep "^GID_MAX" /etc/login.defs | awk '{print $2}')
	current_min_uid=$(grep "^UID_MIN" /etc/login.defs | awk '{print $2}')
	current_min_gid=$(grep "^GID_MIN" /etc/login.defs | awk '{print $2}')

	# Check and update MAX_UID if necessary
	if [ "$USER_UID" -gt "$current_max_uid" ]; then
		echo "Updating UID_MAX from $current_max_uid to $USER_UID"
		sed -i "s/^UID_MAX.*/UID_MAX ${USER_UID}/" /etc/login.defs
	fi

	# Check and update MAX_GID if necessary
	if [ "$USER_GID" -gt "$current_max_gid" ]; then
		echo "Updating GID_MAX from $current_max_gid to $USER_GID"
		sed -i "s/^GID_MAX.*/GID_MAX ${USER_GID}/" /etc/login.defs
	fi

	# Check and update MIN_UID if necessary
	if [ "$USER_UID" -lt "$current_min_uid" ]; then
		echo "Updating UID_MIN from $current_min_uid to $USER_UID"
		sed -i "s/^UID_MIN.*/UID_MIN ${USER_UID}/" /etc/login.defs
	fi

	# Check and update MIN_GID if necessary
	if [ "$USER_GID" -lt "$current_min_gid" ]; then
		echo "Updating GID_MIN from $current_min_gid to $USER_GID"
		sed -i "s/^GID_MIN.*/GID_MIN ${USER_GID}/" /etc/login.defs
	fi
}

create_user() {
	# Create user if it doesn't exist
	if ! id -u "$USERNAME" >/dev/null 2>&1; then
		echo "Creating user $USERNAME with UID $USER_UID and group $GROUP_NAME with GID $USER_GID"

		# Create group if it doesn't exist
		if ! getent group "$USER_GID" >/dev/null; then
			groupadd --gid "$USER_GID" "$GROUP_NAME"
		else # modify the name
			gname=$(getent group "$USER_GID" | cut -d: -f1)
			groupmod -g "$USER_GID" -n "$GROUP_NAME" "$gname"
		fi

		# Check if the UID is in use
		if getent passwd "$USER_UID" >/dev/null; then
			echo "Warning: UID $USER_UID is already in use. Creating the user with UID $DEFAULT_UID instead." >&2
			USER_UID=$DEFAULT_UID
		fi

		# Create user if it doesn't exist
		if ! getent passwd "$USERNAME" >/dev/null; then
			useradd --uid "$USER_UID" --gid "$USER_GID" -m "$USERNAME"
		fi

		# Add current (arbitrary) user to /etc/passwd and /etc/group
		if ! whoami >/dev/null 2>&1; then
			if [ -w /etc/passwd ]; then
				echo "Updating passwd file"
				echo "${USERNAME:-user}:x:$(id -u):0:${USERNAME:-user} user:${HOME}:/bin/bash" >>/etc/passwd
				echo "${USERNAME:-user}:x:$(id -u):" >>/etc/group
			fi
		fi
	fi
}

fix_permissions() {
	echo "Fixing permissions for user $USERNAME ..."
	chown "${USERNAME}:${GROUP_NAME}" -R "$HOME"
	chown "${USERNAME}:${GROUP_NAME}" -R /opt
	chown "${USERNAME}:${GROUP_NAME}" -R "$WORKSPACE"
	mkdir -p "/run/user/${USER_UID}"
	chown "${USERNAME}:${GROUP_NAME}" "/run/user/${USER_UID}"
}

##
## Main
##

# Parse command-line arguments
args=$(getopt -o u:G:g:i: --long user:,group:,gid:,id: -n "$0" -- "$@") || usage

eval set -- "$args"
while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		;;
	-u | --user)
		username="$2"
		shift 2
		;;
	-G | --group)
		group_name="$2"
		shift 2
		;;
	-g | --gid)
		usergid="$2"
		shift 2
		;;
	-i | --id)
		userid="$2"
		shift 2
		;;
	--)
		shift
		break
		;;
	*)
		echo "Unsupported option: $1" >&2
		usage
		;;
	esac
done

# Validate required parameters
if [ -z "$username" ] || [ -z "$usergid" ] || [ -z "$userid" ]; then
	echo "Error: --user, --id, and --gid are required." >&2
	usage
fi

DEFAULT_UID=1000
USERNAME="$username"
GROUP_NAME="${group_name:-$username}"
USER_UID="$userid"
USER_GID="$usergid"
HOME="/home/${USERNAME}"

if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
	echo "Creating user $USERNAME ..."
	update_max_uid_gid
	create_user
	fix_permissions

	if [ -n "${ROCM_VERSION:-}" ]; then
		echo "Adding the user $USERNAME to the video and render groups ..."
		usermod -aG video,render "$USERNAME"
	fi

	install_sudo
else
	echo "No user specified or user is root, not creating a user ..."
fi
