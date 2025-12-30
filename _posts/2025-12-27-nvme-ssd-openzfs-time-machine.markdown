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
*Xlpierrelx, CC BY-SA 3.0 <https://creativecommons.org/licenses/by-sa/3.0>, via Wikimedia Commons*

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

## Guide to using Time Machine with OpenZFS
TBC

Extra Notes (do not remove yet):
Crucial P310 1TB PCIe Gen4 NVMe 2230 M.2 SSD

