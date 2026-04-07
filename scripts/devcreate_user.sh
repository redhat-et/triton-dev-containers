#! /bin/bash -e

trap "echo -e '\nScript interrupted. Exiting gracefully.'; exit 1" SIGINT

# Copyright (C) 2024-2026 Red Hat, Inc.
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

DEFAULT_UID=1000
USER_ID=${USER_UID:-1000}
GROUP_ID=${USER_GID:-1000}

install_sudo() {
	echo "Installing and configuring sudo for $USERNAME ..."
	dnf -y install sudo
	tee -a /etc/sudoers.d/"$USERNAME" <<EOF
# Enable the user account to run sudo without a password
$USERNAME ALL=(ALL) NOPASSWD:ALL
EOF
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
	if [ "$USER_ID" -gt "$current_max_uid" ]; then
		echo "Updating UID_MAX from $current_max_uid to $USER_ID"
		sed -i "s/^UID_MAX.*/UID_MAX $USER_ID/" /etc/login.defs
	fi

	# Check and update MAX_GID if necessary
	if [ "$GROUP_ID" -gt "$current_max_gid" ]; then
		echo "Updating GID_MAX from $current_max_gid to $GROUP_ID"
		sed -i "s/^GID_MAX.*/GID_MAX $GROUP_ID/" /etc/login.defs
	fi

	# Check and update MIN_UID if necessary
	if [ "$USER_ID" -lt "$current_min_uid" ]; then
		echo "Updating UID_MIN from $current_min_uid to $USER_ID"
		sed -i "s/^UID_MIN.*/UID_MIN $USER_ID/" /etc/login.defs
	fi

	# Check and update MIN_GID if necessary
	if [ "$GROUP_ID" -lt "$current_min_gid" ]; then
		echo "Updating GID_MIN from $current_min_gid to $GROUP_ID"
		sed -i "s/^GID_MIN.*/GID_MIN $GROUP_ID/" /etc/login.defs
	fi
}

create_user() {
	# Create user if it doesn't exist
	if ! id -u "$USERNAME" >/dev/null 2>&1; then
		echo "Creating user $USERNAME with UID $USER_ID and GID $GROUP_ID"

		# Create group if it doesn't exist
		if ! getent group "$GROUP_ID" >/dev/null; then
			groupadd --gid "$GROUP_ID" "$USERNAME"
		else # modify the name
			gname=$(getent group "$GROUP_ID" | cut -d: -f1)
			groupmod -g "$GROUP_ID" -n "$USERNAME" "$gname"
		fi

		# Check if the UID is in use
		if getent passwd "$USER_ID" >/dev/null; then
			echo "Warning: UID $USER_ID is already in use. Creating the user with UID $DEFAULT_UID instead." >&2
			USER_ID=$DEFAULT_UID
		fi

		# Create user if it doesn't exist
		if ! getent passwd "$USERNAME" >/dev/null; then
			useradd --uid "$USER_ID" --gid "$GROUP_ID" -m "$USERNAME"
		fi

		# Add current (arbitrary) user to /etc/passwd and /etc/group
		if ! whoami >/dev/null 2>&1; then
			if [ -w /etc/passwd ]; then
				echo "update passwd file"
				echo "${USERNAME:-user}:x:$(id -u):0:${USERNAME:-user} user:${HOME}:/bin/bash" >>/etc/passwd
				echo "${USERNAME:-user}:x:$(id -u):" >>/etc/group
			fi
		fi
	fi
}

fix_permissions() {
	echo "Fixing permissions for user $USERNAME ..."
	chown "$USERNAME:$GROUP_ID" -R "$HOME"
	[[ -n "${WORKSPACE:-}" && -d $WORKSPACE ]] && chown "$USERNAME:$GROUP_ID" -R "$WORKSPACE"

	mkdir -p "/run/user/$USER_ID"
	chown "$USERNAME:$GROUP_ID" "/run/user/$USER_ID"
}

get_user_home() {
	local home_dir

	home_dir=$(getent passwd "$USERNAME" | cut -d':' -f6)
	if [ -n "${home_dir:-}" ]; then
		echo "$home_dir"
	else
		echo "Error: could not resolve home directory for user $USERNAME." >&2
		exit 1
	fi
}

setup_bashrc() {
	if [ ! -f "${HOME}/.bashrc" ]; then
		echo "Setting up ${HOME}/.bashrc for user $USERNAME ..."
		install -m 0644 -t "$HOME" \
			/etc/skel/.bash_logout \
			/etc/skel/.bash_profile \
			/etc/skel/.bashrc
	fi

	mkdir -p "${HOME}/.bashrc.d"
}

##
## Main
##

if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
	echo "Creating user $USERNAME ..."
	update_max_uid_gid
	create_user
	install_sudo

	if [ -n "${ROCM_VERSION:-}" ]; then
		echo "Adding the user $USERNAME to the video and render groups ..."
		usermod -aG video,render "$USERNAME"
	fi

	HOME=$(get_user_home)
	export HOME
	setup_bashrc
	fix_permissions
else
	echo "No user specified or user is root, not creating a user ..."
	setup_bashrc
fi
