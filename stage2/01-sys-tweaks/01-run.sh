#!/bin/bash -e

if [ -n "${PUBKEY_SSH_FIRST_USER}" ]; then
	install -v -m 0700 -o 1000 -g 1000 -d "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh
	echo "${PUBKEY_SSH_FIRST_USER}" >"${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
	chown 1000:1000 "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
	chmod 0600 "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
fi

if [ "${PUBKEY_ONLY_SSH}" = "1" ]; then
	sed -i -Ee 's/^#?[[:blank:]]*PubkeyAuthentication[[:blank:]]*no[[:blank:]]*$/PubkeyAuthentication yes/
s/^#?[[:blank:]]*PasswordAuthentication[[:blank:]]*yes[[:blank:]]*$/PasswordAuthentication no/' "${ROOTFS_DIR}"/etc/ssh/sshd_config
fi

on_chroot << EOF
if [ "${ENABLE_SSH}" == "1" ]; then
	systemctl enable ssh
else
	systemctl disable ssh
fi
systemctl enable systemd-networkd
EOF

# systemd-networkd stuff
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/systemd-networkd.service.d"
install -m 0644 files/override.conf "${ROOTFS_DIR}/etc/systemd/system/systemd-networkd.service.d/override.conf"
mkdir "${ROOTFS_DIR}/boot/firmware/systemd-networkd"
cp files/*.network "${ROOTFS_DIR}/boot/firmware/systemd-networkd/"
cp files/wpa_supplicant-wlan0.conf "${ROOTFS_DIR}/boot/firmware/systemd-networkd/wpa_supplicant-wlan0.conf"
on_chroot << EOF
ln -s /boot/firmware/systemd-networkd/*.network /etc/systemd/network
mkdir /etc/wpa_supplicant
ln -s /boot/firmware/systemd-networkd/wpa_supplicant-wlan0.conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
# systemctl enable wpa_supplicant@wlan0.service:
ln -s /usr/lib/systemd/system/wpa_supplicant@.service /etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service
EOF

# load additional modules
cat files/modules > "${ROOTFS_DIR}/etc/modules"

if [ "${USE_QEMU}" = "1" ]; then
	echo "enter QEMU mode"
	install -m 644 files/90-qemu.rules "${ROOTFS_DIR}/etc/udev/rules.d/"
	echo "leaving QEMU mode"
fi


on_chroot <<- EOF
	systemctl enable rpi-resize

	for GRP in input spi i2c gpio; do
		groupadd -f -r "\$GRP"
	done
	for GRP in adm dialout cdrom audio users sudo video games plugdev input gpio spi i2c render; do
		adduser $FIRST_USER_NAME \$GRP
	done
EOF

if [ "${PASSWORDLESS_SUDO}" = "1" ]; then
	on_chroot <<- EOF
		SUDO_USER="${FIRST_USER_NAME}" raspi-config nonint do_sudo_pass 1
	EOF
fi

on_chroot << EOF
setupcon --force --save-only -v
EOF

on_chroot << EOF
usermod --pass='*' root
EOF

rm -f "${ROOTFS_DIR}/etc/ssh/"ssh_host_*_key*

sed -i 's/^FONTFACE=.*/FONTFACE=""/;s/^FONTSIZE=.*/FONTSIZE=""/' "${ROOTFS_DIR}/etc/default/console-setup"
sed -i "s/PLACEHOLDER//" "${ROOTFS_DIR}/etc/default/keyboard"
on_chroot << EOF
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration console-setup
EOF

if [ -e "${ROOTFS_DIR}/etc/avahi/avahi-daemon.conf" ]; then
  sed -i 's/^#\?publish-workstation=.*/publish-workstation=yes/' "${ROOTFS_DIR}/etc/avahi/avahi-daemon.conf"
fi

# stuff for eb 2.0 Mash image
install -m 644 files/99-lcd.rules "${ROOTFS_DIR}/etc/udev/rules.d/"
mkdir "${ROOTFS_DIR}/etc/systemd/system/webmash.service.d"
install -m 644 files/webmash.service.override.conf "${ROOTFS_DIR}/etc/systemd/system/webmash.service.d/override.conf"
install -m 644 files/mashctld.conf "${ROOTFS_DIR}/etc/mashctld.conf"
on_chroot << EOF
  # group gpio does not exist yet on install time of web20mash
  usermod -G gpio webmash
EOF

