#!/bin/bash
# Nacarat OS Installer - Arch Linux based installation script
# 
# Usage:
#   sudo ./nacaratinstaller.sh [DISK] [ROOT_PASS] [USER_PASS]
#
# Examples:
#   sudo ./nacaratinstaller.sh /dev/sda           # Interactive mode (prompts for passwords)
#   sudo ./nacaratinstaller.sh /dev/sda "pass123" "user123"  # Non-interactive with plain passwords
#   sudo ./nacaratinstaller.sh /dev/nvme0n1       # NVMe disk support
#
# Environment Variables:
#   ROOT_PASS - Root password (optional, will prompt if not set)
#   USER_PASS - User password (optional, will prompt if not set)
#
# Requirements:
#   - Arch Linux live environment
#   - Internet connection
#   - Root privileges
#   - Target disk must be empty (will be repartitioned)
#

BASE_PACKAGES=(
    'base'
    'linux-firmware'
    'amd-ucode'
    'intel-ucode'
    'mkinitcpio'
    'archlinux-keyring'
    'arch-install-scripts'
    'sudo'
    'polkit'
    'pacman-contrib'
    'grub'
    'efibootmgr'
    'dosfstools'
    'e2fsprogs'
    'exfatprogs'
    'ntfs-3g'
    'parted'
    'nvme-cli'
    'cryptsetup'
    'lvm2'
    'networkmanager'
    'openssh'
    'rsync'
    'wget'
    'mesa'
    'nvidia-utils'
    'pipewire'
    'alsa-utils'
    'xorg'
    'sddm'
    'plasma-desktop'
    'dolphin'
    'konsole'
    'vim'
    'nano'
    'zsh'
    'gcc'
    'make'
    'python-pip'
    'npm'
    'noto-fonts'
    'ttf-dejavu'
    'open-vm-tools'
)

KEYMAP="tr"
LOCALE="tr_TR.UTF-8"
ZONE="Europe/Istanbul"
HOSTNAME="nacaratOS-live"
USERNAME="nacarat"
FS="ext4"

set -euo pipefail
IFS=$'\n\t'

TARGET_DISK="${1:-/dev/sda}"
ROOT_PASS="${2:-}"
USER_PASS="${3:-}"

log() { echo "[nacarat] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root." >&2
        exit 1
    fi
}

part_suffix() {
    # /dev/sda -> /dev/sda1 ; /dev/nvme0n1 -> /dev/nvme0n1p1
    case "$1" in
        /dev/nvme*) echo "${1}p$2" ;;
        *) echo "${1}$2" ;;
    esac
}

confirm() {
    read -rp "$1 [y/N]: " ans
    case "$ans" in
        [Yy]* ) return 0 ;;
        *) return 1 ;;
    esac
}

setupdisk() {
    log "Partitioning ${TARGET_DISK} (GPT, ESP + root)"
    if [ ! -b "$TARGET_DISK" ]; then
        log "ERROR: Disk $TARGET_DISK not found!" >&2
        exit 1
    fi
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary "${FS}" 513MiB 100%
}

format_and_mount() {
    PART1=$(part_suffix "$TARGET_DISK" 1)
    PART2=$(part_suffix "$TARGET_DISK" 2)

    log "Formatting $PART1 as FAT32 and $PART2 as ${FS}"
    mkfs.fat -F32 "$PART1"
    mkfs -t "${FS}" "$PART2"

    log "Mounting root and boot"
    mount "$PART2" /mnt
    mkdir -p /mnt/boot
    mount "$PART1" /mnt/boot
}

installpkg() {
    log "Installing base packages to /mnt"
    pacman -Sy --noconfirm
    pacstrap -K /mnt "${BASE_PACKAGES[@]}"
    log "Base packages installed"
}

generate_fstab() {
    log "Generating fstab"
    genfstab -U /mnt > /mnt/etc/fstab
}

configure_system() {
    log "Configuring system (timezone, locale, hostname, users, bootloader)"
    arch-chroot /mnt /bin/bash -e <<EOF
set -e

# Export variables into chroot environment
export ZONE="${ZONE}"
export LOCALE="${LOCALE}"
export KEYMAP="${KEYMAP}"
export USERNAME="${USERNAME}"
export HOSTNAME="${HOSTNAME}"
export ROOT_PASS="${ROOT_PASS}"
export USER_PASS="${USER_PASS}"

ln -sf /usr/share/zoneinfo/\${ZONE} /etc/localtime
hwclock --systohc
sed -i "s/#\${LOCALE}/\${LOCALE}/" /etc/locale.gen || true
locale-gen
echo "LANG=\${LOCALE}" > /etc/locale.conf
echo "\${HOSTNAME}" > /etc/hostname
echo "KEYMAP=\${KEYMAP}" > /etc/vconsole.conf

# Root şifresi
if [ -n "\${ROOT_PASS}" ]; then
    echo "root:\${ROOT_PASS}" | chpasswd
else
    echo "Set root password:"
    passwd
fi

# Kullanıcı oluşturma
useradd -m -G wheel -s /bin/zsh \${USERNAME} 2>/dev/null || true

# Kullanıcı şifresi
if [ -n "\${USER_PASS}" ]; then
    echo "\${USERNAME}:\${USER_PASS}" | chpasswd
else
    echo "Set password for \${USERNAME}:"
    passwd \${USERNAME}
fi

sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers || true

# Servisler
systemctl enable NetworkManager || true
systemctl enable sddm || true

# Bootloader ve Initramfs
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=nacarat
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
EOF
}

cleanup() {
    log "Unmounting and finishing"
    umount -R /mnt || true
}

trap cleanup EXIT

main() {
    check_root
    log "Target disk: ${TARGET_DISK}"
    if ! confirm "This will erase ${TARGET_DISK}. Continue?"; then
        log "Aborted by user"
        exit 1
    fi

    setupdisk
    format_and_mount
    installpkg
    generate_fstab
    configure_system
    log "Installation finished. Reboot into new system."
}

main "$@"