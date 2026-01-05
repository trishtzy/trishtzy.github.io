---
layout: post
title:  "Using openzfs to manage backups in macOS"
date:   2025-12-27 00:00:00 +0800
tags: [openzfs, time machine, nvme, ssd]
---

Hello world, today I'm writing yet another how-to guide. This time, on how to backup macOS using NVMe SSDs instead of external (portable) SSDs. The goal is to allow anyone to backup their Mac without worrying about failure modes like broken or missing external disks — maybe it got stolen, or you forgot where you left it. Using multiple NVMe SSDs with OpenZFS is a reliable way to solve this problem.

## A brief history of external drives

External drives can refer to either hard disk drive (HDD) or solid state drive (SSD). They are often used as secondary storage devices. Sometimes you use it to store films, videos, photos or simply use it as a Time Machine to backup important documents in case your computer fails.

### HDD

HDD stores data using magnetic storage with one or more rotating platters coated with magnetic material. The platters are paired with a magnetic head, usually arranged on a moving actuator arm, which reads and writes data to the platter surface. The head has a magnetic core and passes over the magnetized sections of the platter measuring changes in the direction of the magnetic poles. Using Faraday's law, a change in magnetization produces a voltage in a nearby coil. As the head flies over the platter surface where the polarity has changed, it records a voltage spike. These spikes, both negative and positive represent a 1, while no voltage spike represents a 0.

![hdd](https://upload.wikimedia.org/wikipedia/commons/0/05/Illustration_of_the_parts_of_a_hard_disk%2C_with_labels.jpg)
Figure 1. *Xlpierrelx, CC BY-SA 3.0 <https://creativecommons.org/licenses/by-sa/3.0>, via Wikimedia Commons*

A popular external portable HDD back in 2010 was Western Digital's My Passport. Nowadays, most people opt for SSDs as their external storage device. This is because HDD is prone to many failure modes. It is vulnerable to being damaged by a head crash where the head scrapes across the platter surface. The head may touch the platter due to sudden power failure, physical shock (when you drop the disk), or simply wear and tear. The HDD's spindle system relies on air density inside the disk enclosure to support the heads at their proper flying height while the disk rotates. So if the air density is too low, the head may get too close to the disk and risk data loss from head crash.

How can you tell if a HDD is failing?

- You hear clicking, grinding, or beeping
- Slow performance
- It freezes or crashes when connected or opening files
- Disk Utility shows an error

### SSD

An SSD uses flash memory to store data. It means it stores electrons in a charge trap to determine if it's 1 or 0. The main advantage of using SSD is that it has no moving parts and is resistant to physical shock unlike HDD with the floating mechanical arm.

There are many nuanced differences in SSD manufacturing—from the number of bits stored per cell to memory architecture. I'm not familiar with all of it, but the key trade-off is this: single-level cells (SLC) store just one bit (0 or 1) and offer the best endurance, while quad-level cells (QLC) pack 4 bits per cell but wear out faster. The endurance ranking goes SLC > MLC > TLC > QLC.

I'm using multiple Crucial P310 1TB SSDs for my Time Machine backup. This model is marketed for gaming purposes. It uses QLC NAND flash, which is tolerable for gaming and archival purposes since those are mostly read-heavy. For video editing, anything better than QLC (TLC or above) makes more sense, since video editing involves heavy write workloads.

Why is that so? QLC's main drawbacks are write-related. With 4 bits per cell, it has 16 voltage states to manage, which makes writing slower and more error-prone. For backup workloads though, this is acceptable as backups are write-once, read-rarely.

So why manage backups with NVMe SSDs using OpenZFS instead of external SSDs with Time Machine?

- **Faster read/write speeds.** NVMe SSDs are significantly faster than portable SSDs. For example, the Samsung Portable SSD T9 offers sequential read/write speeds of up to 2,000 MB/s through USB 3.2 Gen 2. NVMe SSDs connected directly to your Mac can achieve speeds of 3,500 MB/s or more.

- **Parallel redundancy.** OpenZFS lets you mirror or stripe multiple drives, so you can backup your backup automatically.

- **Proactive failure detection.** OpenZFS monitors drive health and notifies you of issues before data loss occurs. Compare this to Time Machine, which only alerts you when it can no longer read or write to the disk.

### SATA vs NVMe SSD

SATA (Serial Advanced Technology Attachment) is a specification for connecting storage devices which includes HDDs and SDDs to a computer's motherboard. The specification covers the physical, link, transport and command layers. For example, the specific physical connectors required as well as how the hard drive communicates with the computer.

SATA was created primarily for HDDs and address the limitation of the older interface PATA (Parallel ATA). PATA had signal integrity issues at higher speed and bulky ribbon cables. Hence SATA was created to allow higher data speed.

When SSDs were introduced, it adopted the SATA interface as SATA was the dominant storage bus on most motherboards.

(insert photo of SATA SSD)

However, SATA SSDs often hit SATA's maximum speeds. SATA III the most recent version, tops out at around 6 Gb/s. That translates to ~500-580 MB/s for reads and writes. This limit is due to SATA bus and its legacy protocol AHCI which was originally designed for HDD not SSD.

Because SSD quickly became capable of much higher speeds, SATA became a bottleneck beyond a point of adding more NAND performance. This led to NVMe SSD over PCIe bus. Each PCIe lane delivers ~1GB/s or more. Modern SSDs commonly use x4 PCIe lanes, allowing multiple gigabytes per second of throughput. NVMe (Non-Volatile Memory Express) was designed specifically for SSDs. It supports massive parallelism, lower latency and lower CPU overhead.

![nvme](assets/img/nvme-family-of-specs.png)
Figure 2. NVMe Family of Specifications [reproduced from NVM Express, Inc.,
"NVMe over PCIe Transport Specification," Revision 1.3, July 2025, Figure 1]

Finally, we talk about the form factor. There is M.2 SATA and M.2 PCIe SSD, and both. SATA M.2 drives will have two notches while PCIe SSD has one. There are also SSDs that allow for both interfaces.

## Guide to using Time Machine with OpenZFS

First let's size down our SSD such that we'll be able to replace with SSDs from a different manufacturer. This is because, even though SSDs are marketed as 1TB, the actual free space available may vary.

```sh
❯ diskutil partitionDisk /dev/disk4 GPT \
> ExFAT ZFS1 998G \
> "Free Space" "" R
Started partitioning on disk4
Unmounting disk
Creating the partition map
Waiting for partitions to activate
Formatting disk4s2 as ExFAT with name ZFS1
Volume name      : ZFS1
Partition offset : 411648 sectors (210763776 bytes)
Volume size      : 1949216768 sectors (997998985216 bytes)
Bytes per sector : 512
Bytes per cluster: 131072
FAT offset       : 2048 sectors (1048576 bytes)
# FAT sectors    : 61440
Number of FATs   : 1
Cluster offset   : 63488 sectors (32505856 bytes)
# Clusters       : 7613880
Volume Serial #  : 69562235
Bitmap start     : 2
Bitmap file size : 951735
Upcase start     : 10
Upcase file size : 5836
Root start       : 11
Mounting disk
Finished partitioning on disk4
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *1.0 TB     disk4
   1:                        EFI EFI                     209.7 MB   disk4s1
   2:       Microsoft Basic Data ZFS1                    998.0 GB   disk4s2
                    (free space)                         2.0 GB     -
```

Do the same for the second SSD.

```sh
❯ diskutil list
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *1.0 TB     disk4
   1:                        EFI EFI                     209.7 MB   disk4s1
   2:       Microsoft Basic Data ZFS1                    998.0 GB   disk4s2
                    (free space)                         2.0 GB     -

/dev/disk5 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *1.0 TB     disk5
   1:                        EFI EFI                     209.7 MB   disk5s1
   2:       Microsoft Basic Data ZFS1                    998.0 GB   disk5s2
                    (free space)                         2.0 GB     -

```

We set to ExFAT as a placeholder for ZFS to overwrite it later when we create the zpool.

### Create zpool

Now before we create zpool, we'll need to unmount the disks as macOS automatically mounted them as usable volumes after we formatted them as ExFAT.

```sh
❯ diskutil unmount /dev/disk4s2
Volume ZFS1 on disk4s2 unmounted
~ ·············································································
❯ diskutil unmount /dev/disk5s2
Volume ZFS1 on disk5s2 unmounted
```

Then create the zpool:

```sh
❯ sudo zpool create -f \
-o ashift=12 \
-O compression=lz4 \
-O atime=off \
-O casesensitivity=insensitive \
-O normalization=formD \
backup mirror /dev/disk4s2 /dev/disk5s2
```

### Create a Time Machine Dataset

```sh
❯ sudo zfs create \
> -o encryption=aes-256-gcm \
> -o keyformat=passphrase \
> -o keylocation=prompt \
> -o com.apple.mimic=hfs \
> backup/timemachine
# You will be prompted for a passphrase
```

### Configure Time Machine

```sh
# Get the mount point (should be /Volumes/backup/timemachine)
❯ zfs get mountpoint backup/timemachine
NAME                PROPERTY    VALUE                        SOURCE
backup/timemachine  mountpoint  /Volumes/backup/timemachine  default

# Set as Time Machine destination
sudo tmutil setdestination /Volumes/backup/timemachine
```

### Verify the setup

```sh
# Check pool status and mirror health
zpool status backup

# Check ZFS properties
zfs get all backup/timemachine

# Verify Time Machine destination
tmutil destinationinfo
```

### Enable Auto-Import on boot

```sh
# ZFS pools should auto-import, but verify with:
sudo zpool set cachefile=/etc/zfs/zpool.cache backup
```

### Quick Health Check Commands

```sh
# Check mirror status (both drives should show ONLINE)
zpool status

# Run a scrub to verify data integrity (do this monthly)
sudo zpool scrub backup

# Check scrub progress
zpool status backup
```

Note to self (do not remove yet):

- Crucial P310 1TB PCIe Gen4 NVMe 2230 M.2 SSD
- https://www.amazon.com/Blue-NAND-1TB-SSD-WDS100T2B0B/dp/B073SB2MXT
