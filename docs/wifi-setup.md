
# 2.4 GHz RF Planning Guide (WiFi, Zigbee, Thread)

This document describes how to inspect 2.4 GHz spectrum usage on Linux systems and how to select suitable channels for WiFi, Zigbee, and Thread networks in a mixed environment.

## 1. Inspecting 2.4 GHz WiFi Activity (Linux)

Use nmcli to scan nearby access points:

```bash
nmcli -f SSID,CHAN,SIGNAL dev wifi
```

```bash
sudo iwlist scan | grep -e "Channel:" -e "Signal"
```

Record for each of the WiFi channels 1, 6, and 11:
- Number of visible networks
- Strength of the strongest network (SIGNAL > -60 dBm indicates high interference)

Choose the WiFi channel (1/6/11) with the lowest interference footprint.


## 2. Inspecting Zigbee Channel Noise

In Home Assistant (ZHA):
```markdown
Settings → Devices → Zigbee → Energy Scan
```

Note noise levels for all Zigbee channels (11–26) and identify the cleanest ones.


## 3. Valid Channel Ranges

WiFi (2.4 GHz)
- Allowed: 1, 6, 11
- Channel width: 20 MHz

Zigbee
- Allowed: 11–26

Thread (Matter)
- Allowed: 11–26
- Channel selection is automatic; no configuration required.

## 4. Channel Selection Procedure

### 4.1 Select WiFi Channel

Choose one of 1/6/11 based on the Linux scan:
- Prefer the channel with the fewest nearby APs
- Avoid channels with strong (>-60 dBm) neighbouring signals

### 4.2 Select Zigbee Channel Based on WiFi

Avoid Zigbee channels that overlap heavily with the chosen WiFi channel.

WiFi Channel	Avoid Zigbee Channels	Recommended Zigbee Channels
1	11–15	16–20
6	15–20	21–25
11	20–26	11–15

Recommended Zigbee Defaults
- Channel 15 – general-purpose choice, good isolation in most setups
- Channel 20 – good option when WiFi is on channel 1
- Channel 25 – good option when WiFi is on channel 6

### 4.3 Thread

No manual configuration. The Thread Border Router selects a channel automatically and adapts to existing WiFi/Zigbee usage.


## 5. Hardware Considerations

For Zigbee radios connected to Linux servers:
- Prefer USB 2.0 ports
- Use a 1–2 m USB extension cable to distance the radio from the server chassis
- Avoid placement near USB 3.0 ports, SSDs, switches, and power supplies
- Mount the dongle in open air, away from metal surfaces

## 6. Quick Summary

- Scan WiFi on Linux → select channel 1, 6, or 11 based on lowest measured interference.
- Select a Zigbee channel that does not overlap with the chosen WiFi channel (see table above).
- Thread requires no changes.
- Position the Zigbee dongle to minimize local EMI.