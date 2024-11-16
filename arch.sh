#!/bin/bash

clear

# Cosmetics (colours for text).
BOLD='\e[1m'
BRED='\e[91m'
BBLUE='\e[34m'
BGREEN='\e[92m'
BYELLOW='\e[93m'
RESET='\e[0m'

# Pretty print (function).
info_print () {
    echo -e "${BOLD}${BGREEN}[ ${BYELLOW}•${BGREEN} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

userpass_selector () {
    input_print "Enter username: "
    read -r username
    if [[ -z "$username" ]]; then
        return 0
    fi
    input_print "Enter password for $username: "
    read -r -s userpass
    if [[ -z "$userpass" ]]; then
        echo
        error_print "You need a password for $username, please try again."
        return 1
    fi
    echo
    input_print "Enter the password again: "
    read -r -s userpass2
    echo
    if [[ "$userpass" != "$userpass2" ]]; then
        echo
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

rootpass_selector () {
    input_print "Enter a password for the root user: "
    read -r -s rootpass
    if [[ -z "$rootpass" ]]; then
        echo
        error_print "You need a password for root, please try again."
        return 1
    fi
    echo
    input_print "Enter the password again: "
    read -r -s rootpass2
    echo
    if [[ "$rootpass" != "$rootpass2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

hostname_selector () {
    input_print "Please enter the hostname: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
        error_print "You need to enter a hostname in order to continue."
        return 1
    fi
    return 0
}

# List available disks
lsblk

# Ask for target disk
read -p "Enter the target disk (e.g., /dev/sda): " TARGET_DISK

# Create GPT partition table
parted $TARGET_DISK mklabel gpt

# Create EFI partition (1GB)
parted $TARGET_DISK mkpart primary fat32 1MiB 1GiB
parted $TARGET_DISK set 1 boot on

# Create swap partition (4GB)
parted $TARGET_DISK mkpart primary linux-swap 1GiB 5GiB

# Create root partition (remaining space)
parted $TARGET_DISK mkpart primary ext4 5GiB 100%

# Format partitions
mkfs.fat -F32 ${TARGET_DISK}1  # EFI partition
mkswap ${TARGET_DISK}2  # Swap partition
mkfs.ext4 ${TARGET_DISK}3  # Root partition

# Enable swap
swapon ${TARGET_DISK}2

# Mount root partition
mount ${TARGET_DISK}3 /mnt

# Mount EFI partition
mkdir -p /mnt/boot/efi
mount ${TARGET_DISK}1 /mnt/boot/efi

# Install base system, GRUB, and required packages
pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr

# Generate fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt <<EOF

	# Set the timezone
	ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
	hwclock --systohc

	# Set locale
	sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf

	# Set hostname
	echo "$hostname" > /etc/hostname

	# Install GRUB (UEFI)
	grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
	grub-mkconfig -o /boot/grub/grub.cfg

EOF

# User sets up the user/root passwords.
until userpass_selector; do : ; done
until rootpass_selector; do : ; done

# Setting root password.
info_print "Setting root password."
echo "root:$rootpass" | arch-chroot /mnt chpasswd

# Setting user password.
if [[ -n "$username" ]]; then
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    info_print "Adding the user $username to the system with root privilege."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    info_print "Setting user password for $username."
    echo "$username:$userpass" | arch-chroot /mnt chpasswd
fi

# Unmount and reboot
umount -R /mnt
reboot

