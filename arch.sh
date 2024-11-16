#!/bin/bash

get_and_confirm_input() {
    local prompt="$1"
    local input1 input2
    while true; do
        # First input
        read -p "$prompt" input1
        # Second input (confirmation)
        read -p "Confirm $prompt: " input2

        # Check if the two inputs match
        if [[ "$input1" == "$input2" ]]; then
            break
        else
            echo "Inputs do not match"
        fi
    done
}

# List available disks
lsblk

# Ask for target disk
read -p "Enter the target disk (e.g., /dev/sda): " TARGET_DISK
rootpasswd=$(get_and_confirm_input "Please enter password for ROOT: ")
username=$(get_and_confirm_input "Please enter your username: ")
userpasswd=$(get_and_confirm_input "Please enter password: ")

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
echo "myarch" > /etc/hostname

# Network settings
echo "127.0.0.1   localhost" > /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   myarch.localdomain myarch" >> /etc/hosts

# Install GRUB (UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Create user
useradd -m -G wheel $username
echo -e "$userpasswd\n$userpasswd" | passwd "$username"

# Set root password
echo -e "$rootpasswd\n$rootpasswd" | passwd

# Enable sudo for the user (require "wheel" group)
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

EOF

# Unmount and reboot
umount -R /mnt
reboot

