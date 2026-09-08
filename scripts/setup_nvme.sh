#!/bin/bash
set -e

# Partition
sudo parted /dev/nvme1n1 mklabel gpt
sudo parted /dev/nvme1n1 mkpart primary ext4 0% 100%
sudo parted /dev/nvme2n1 mklabel gpt
sudo parted /dev/nvme2n1 mkpart primary ext4 0% 100%

# Format
sudo mkfs.ext4 /dev/nvme1n1p1
sudo mkfs.ext4 /dev/nvme2n1p1

# Create mount points
sudo mkdir -p /mnt/nvme1 /mnt/nvme2

# Mount
sudo mount /dev/nvme1n1p1 /mnt/nvme1
sudo mount /dev/nvme2n1p1 /mnt/nvme2

# Show UUIDs for fstab
echo "Add these to /etc/fstab:"
blkid /dev/nvme1n1p1 /dev/nvme2n1p1
