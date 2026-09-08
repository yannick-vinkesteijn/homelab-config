# Acasis NVMe Enclosure Setup Guide — Mac mini 2018 + Ubuntu Server

## Hardware

- **Host:** Mac mini Late 2018 (Intel Coffee Lake), 4× Thunderbolt 3 ports
- **Enclosure:** Acasis 40Gbps M.2 NVMe 2-Bay RAID SSD Enclosure (TBU405ProMax)
  - Intel JHL7440 Thunderbolt 3 controller
  - 2× M.2 2280 NVMe slots, 8TB max per slot
  - 65W external PSU included
  - ~1500 MB/s per drive in JBOD, ~2800 MB/s in RAID 0
- **Drives:** 2× Lexar NM790 4TB M.2 2280 NVMe (without heatsink)
  - Model: LNM790X004T-RNNNG
  - 232-layer TLC NAND, 3000 TBW endurance, 5-year warranty

## Prerequisites

- Ubuntu Server installed on the Mac mini
- SSH access working
- Ghostty terminal users: export `TERM=xterm-256color` before SSH, or install terminfo on server:
  ```bash
  # run from local Mac, not over SSH
  infocmp -x xterm-ghostty | ssh user@<ip> 'tic -x -'
  ```

## Step 1: Fix Thunderbolt crash on device connect

The Mac mini's Thunderbolt 3 host controller can freeze the system when a new TB3 device connects while security is set to `user` mode. Adding a kernel parameter prevents this.

```bash
sudo nano /etc/default/grub
```

Find `GRUB_CMDLINE_LINUX_DEFAULT` and add `thunderbolt.host_reset=0`:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash thunderbolt.host_reset=0"
```

Apply and reboot:

```bash
sudo update-grub
sudo reboot
```

## Step 2: Connect the enclosure

**Order matters:**

1. Insert NVMe drives into the Acasis enclosure (tool-free magnetic bays)
2. Plug the Acasis 65W PSU into the wall and the enclosure
3. Connect the Thunderbolt cable from the Acasis to a free TB3 port on the Mac mini

If the Mac mini has other TB devices, try using a port on the other bus. The 4 TB3 ports are split across two buses: the two ports closer to HDMI are one bus, the two closer to the power plug are the other.

## Step 3: Authorize the Thunderbolt device

Check if the enclosure is visible:

```bash
boltctl list
```

It should show the Acasis as `connected` but not authorized. Enroll it with auto policy so it's trusted on every boot:

```bash
sudo boltctl enroll --policy auto <device-uuid>
```

Verify it shows `status: authorized` and the drives appear:

```bash
lsblk
```

You should see two new NVMe devices (`/dev/nvme1n1`, `/dev/nvme2n1` or similar). If they show as `/dev/sd*` instead, the connection fell back to USB and you're not getting TB3 speeds.

## Step 4: Partition and format

```bash
# Partition both drives
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
```

## Step 5: Remove reserved space

ext4 reserves 5% for root by default. On a 3.7TB data drive that's ~185GB wasted. Remove it:

```bash
sudo tune2fs -m 0 /dev/nvme1n1p1
sudo tune2fs -m 0 /dev/nvme2n1p1
```

## Step 6: Add to fstab

Get the UUIDs:

```bash
blkid /dev/nvme1n1p1 /dev/nvme2n1p1
```

Edit fstab:

```bash
sudo nano /etc/fstab
```

Add (replace UUIDs with your actual values):

```
UUID=<nvme1-uuid> /mnt/nvme1 ext4 defaults,nofail 0 2
UUID=<nvme2-uuid> /mnt/nvme2 ext4 defaults,nofail 0 2
```

The `nofail` flag is important — it prevents the system from dropping into emergency mode if the Acasis is disconnected or slow to authorize at boot.

Verify:

```bash
sudo mount -a
df -h /mnt/nvme1 /mnt/nvme2
```

Both should show ~3.7TB available.

## Verification

Confirm drives are running over Thunderbolt (not USB fallback):

```bash
# Should show /dev/nvme* devices, not /dev/sd*
lsblk

# Should show authorized at 40 Gb/s
boltctl list

# Check drive health
sudo smartctl -a /dev/nvme1n1
sudo smartctl -a /dev/nvme2n1
```

## Troubleshooting

### System freezes when plugging in the Acasis
- Unplug the Thunderbolt cable (not just the PSU)
- Hold power button 5-10 seconds to force shutdown
- Boot without the Acasis connected
- Verify `thunderbolt.host_reset=0` is in your GRUB config
- Run `sudo update-grub` and reboot before trying again

### Drives don't appear after authorization
- Check `dmesg | tail -30` for NVMe enumeration errors
- Try a different TB3 port (different bus)
- Ensure PSU is connected to the Acasis before the TB cable

### Drives show as /dev/sd* instead of /dev/nvme*
- The connection fell back to USB mode (~1000 MB/s instead of ~1500 MB/s)
- Check `boltctl list` — device may need re-authorization
- Try unplugging and reconnecting (PSU first, then TB cable)

### SSH terminal error: "Error opening terminal: xterm-ghostty"
```bash
export TERM=xterm-256color
```

### Can I start with one drive and add the second later?
Yes. The two bays are independent. Insert one drive, complete the setup for that drive only, and add the second whenever ready. No reconfiguration needed.
