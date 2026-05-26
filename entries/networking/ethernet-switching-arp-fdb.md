---
title: "Ethernet Switching: ARP, MAC Learning, and the FDB"
slug: ethernet-switching-arp-fdb
topic: networking
tags: [networking, ethernet, l2, arp, switching, fdb, bridge, broadcast, jargon]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
On a local network, machines deliver data to each other by **MAC address** — but a
machine usually starts out knowing only the *IP* of who it wants to reach, not the
MAC. **ARP** (Address Resolution Protocol) is the "who has this IP?" broadcast that
discovers the matching MAC. Once frames are flowing, a **switch** (or a Linux bridge,
which is a software switch) delivers each frame to the correct **port** by remembering
which MAC was last seen on which port — a self-built table called the **forwarding
database (FDB)**. Frames whose destination MAC is unknown, or that are broadcasts,
are **flooded** out every port. This is exactly how two VMs on the same bridge talk
to each other, with no IP routing involved.

## Details

### The problem ARP solves
To put a frame on the wire you must fill in the **destination MAC**. But you typically
only know the destination **IP** (you typed `ssh 10.42.0.8`). ARP bridges that gap:
**IP → MAC**.

### ARP, step by step (A wants to reach B at 10.42.0.8)
1. **A checks: is 10.42.0.8 local?** Using its subnet mask, yes → "I can reach it
   directly, no gateway." (If it weren't local, A would ARP for the *gateway* instead.)
2. **A broadcasts an ARP request:** "who has `10.42.0.8`? tell `10.42.0.7`." The
   frame's destination MAC is `ff:ff:ff:ff:ff:ff` — the **broadcast** address (everyone).
3. **B replies (unicast):** "`10.42.0.8` is at `aa:bb:cc:dd:ee:02`."
4. **A caches it** in its **ARP cache** (an IP→MAC table inside the machine). Future
   sends to B skip ARP entirely.

### The switch / bridge and MAC learning
A switch is an L2 device with **ports** (each cable/VM is a port). It is
self-configuring through **MAC learning**: for every frame it sees, it records
`source MAC → the port it arrived on` into its **forwarding database (FDB)**. It then
forwards by **destination** MAC:
- **Known unicast** (dst MAC is in the FDB) → send out *only* that one port.
- **Unknown unicast or broadcast** → **flood**: send out every port *except* the one
  it arrived on. (The eventual reply teaches the switch where that MAC lives.)
- FDB entries **age out** after a period of inactivity (~300 s / 5 min by default),
  so stale mappings are forgotten.

### Worked example: VM-A → VM-B on the same bridge
```
1. A broadcasts "who has 10.42.0.8?"  →  bridge floods to ALL ports (B, C, host…)
2. B replies "that's me, MAC ..:02"   →  bridge learns  ..:02 → port tap-B (FDB)
                                          A learns 10.42.0.8 → ..:02 (ARP cache)
3. A sends real data to MAC ..:02      →  bridge forwards ONLY out tap-B (unicast)
```
After step 2, no more flooding and no more ARP — it's direct port-to-port switching.
This never touches the host's IP routing, NAT, or any uplink: **pure L2,
host-internal.**

### Two tables people confuse
| Table | Lives in | Maps | Built by |
|---|---|---|---|
| **ARP cache** | the sending machine (guest/host) | IP → MAC | ARP request/reply |
| **FDB** | the switch / bridge | MAC → port | MAC learning (watching source MACs) |

### Jargon, glossed simply
- **ARP** — the protocol that asks "who has this IP?" to learn the matching MAC.
- **Broadcast** — a frame sent to everyone on the segment (dst MAC `ff:ff:ff:ff:ff:ff`).
- **Unicast** — a frame sent to exactly one MAC.
- **Flood** — forward a frame out every port (used when the destination port is unknown, or for broadcasts).
- **MAC learning** — a switch recording which MAC is on which port by watching incoming frames.
- **FDB (forwarding database)** — the switch's MAC→port table.
- **ARP cache** — the sender's IP→MAC table.
- **Aging** — forgetting FDB/ARP entries after they've been idle a while.
- **Port** — one connection point on a switch (here, one VM's TAP).

## Key points
- You send Ethernet frames by destination MAC, but usually only know the IP — ARP resolves IP → MAC.
- An ARP request is a broadcast ("who has 10.42.0.8?"); the owner answers with a unicast reply giving its MAC.
- The sender caches the result in its ARP cache (IP→MAC) and skips ARP on later sends.
- A switch/bridge learns by recording source-MAC → arrival-port into its forwarding database (FDB).
- Known-unicast frames go out only the learned port; unknown-unicast and broadcast frames are flooded to all other ports.
- FDB (and ARP) entries age out after idle (~300 s default), so stale mappings are dropped.
- ARP cache (IP→MAC, in the host) and FDB (MAC→port, in the switch) are two different tables in two different places.
- VM-to-VM traffic on one bridge is pure L2 switching — it never touches IP routing, NAT, or the uplink.

## References
- RFC 826 — Address Resolution Protocol (ARP).
- IEEE 802.1D — bridging / MAC learning behavior.
- Linux bridge documentation (FDB, flooding, default ~300 s aging).

## Related
- [Network Layers: L2 (Ethernet) vs L3 (IP)](network-layers-l2-l3.md) — what "L2" and "MAC" mean.
- [IP Routing, Default Gateways, and ip_forward](ip-routing-and-gateways.md) — what happens when the destination is *not* local.
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — the bridge as the VMs' switch.
