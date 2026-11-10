#!/usr/bin/env bash
set -Eeuo pipefail
DISK=/dev/nvme1n1
LOG=/root/pve-hz2-step128.log
exec > >(tee -a "$LOG") 2>&1
echo "STEP 128: Samsung partition 4"
test "$(id -u)" -eq 0
test "$(hostname -s)" = "pve-hz2"
test "$(blockdev --getsz "$DISK")" = "2000409264"
test -s /root/nvme1n1-before-extra-storage.sfdisk
test ! -e /dev/nvme1n1p4
diff -u /root/nvme1n1-before-extra-storage.sfdisk <(sfdisk --dump "$DISK")
grep -q 'md2 : active raid5' /proc/mdstat
grep -q '\[3/3\] \[UUU\]' /proc/mdstat
test "$(qm status 101)" = "status: running"
echo "Simulating exact partition..."
printf '1000214528,1000194736,83\n' | sfdisk --no-act --append --wipe never --wipe-partitions never "$DISK"
echo "Creating only partition 4..."
printf '1000214528,1000194736,83\n' | sfdisk --append --wipe never --wipe-partitions never "$DISK"
echo "Partition table after operation:"
sfdisk --dump "$DISK"
echo "RAID health:"
cat /proc/mdstat
echo "VM 101:"
qm status 101
echo "Do not format anything yet. Share the output."
