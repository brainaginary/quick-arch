#!/bin/bash

echo "Listing available disks:"
lsblk

# Assuming the target disk is /dev/sda
TARGET_DISK="/dev/vda"

# Create a new GPT partition table
parted $TARGET_DISK mklabel gpt

# Create the EFI partition (1GB)
parted $TARGET_DISK mkpart primary fat32 1MiB 1GiB
parted $TARGET_DISK set 1 boot on

# Create the swap partition (4GB)
parted $TARGET_DISK mkpart primary linux-swap 1GiB 5GiB

# Create the root partition (remaining space)
parted $TARGET_DISK mkpart primary ext4 5GiB 100%

# Format the partitions
mkfs.fat -F32 ${TARGET_DISK}1  # EFI partition
mkfs.ext4 ${TARGET_DISK}3  # Root partition
mkswap ${TARGET_DISK}2  # Swap partition

# Enable swap
swapon ${TARGET_DISK}2

# Mount the root partition
mount ${TARGET_DISK}3 /mnt

# Mount the EFI partition
mkdir /mnt/boot/efi
mount ${TARGET_DISK}1 /mnt/boot/efi

# Install base system
pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr

# Generate the fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt <<EOF

# Set the timezone
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Localization
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
grub-install --target=x86_64-efi --efi-directory=/boot/efi/ --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Set root password
echo "Set the root password"
passwd

EOF

# Exit chroot
exit

# Unmount all partitions
umount -R /mnt

# Reboot the system
reboot

