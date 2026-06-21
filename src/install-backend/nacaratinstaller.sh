BASE_PACKAGES=(
    'base'
    'linux-cachyos-lts'
    'linux-cachyos-lts-headers'
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
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary ${FS} 513MiB 100%
}

format_and_mount() {
    PART1=$(part_suffix "$TARGET_DISK" 1)
    PART2=$(part_suffix "$TARGET_DISK" 2)

    log "Formatting $PART1 as FAT32 and $PART2 as ${FS}"
    mkfs.fat -F32 "$PART1"
    mkfs.${FS} "$PART2"

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
    arch-chroot /mnt /bin/bash -e <<'EOF'
set -e
ln -sf /usr/share/zoneinfo/${ZONE} /etc/localtime
hwclock --systohc
sed -i "s/#${LOCALE}/${LOCALE}/" /etc/locale.gen || true
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname

echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "Set root password now:"
passwd

useradd -m -G wheel -s /bin/zsh ${USERNAME} || true
echo "Set password for ${USERNAME}:"
passwd ${USERNAME}

sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers || true

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=nacarat || true
grub-mkconfig -o /boot/grub/grub.cfg || true

mkinitcpio -P || true
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