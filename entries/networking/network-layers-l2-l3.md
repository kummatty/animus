---
title: "Network Layers: L2 (Ethernet) vs L3 (IP)"
slug: network-layers-l2-l3
topic: networking
tags: [networking, fundamentals, ethernet, ip, l2, l3, encapsulation, mac, jargon]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
Networking is built in **layers**, where each layer has its own kind of address and
its own job, and hands off to the next. Two matter most here. **Layer 2 (L2, the
"link layer," in practice Ethernet)** moves data between machines **on the same
local network**, addressed by **MAC address** (a hardware address baked into/assigned
to each network card). **Layer 3 (L3, the "network layer," IP)** moves data **across
different networks**, addressed by **IP address**, and is what makes the global
internet possible. A higher-layer message rides *inside* a lower-layer one — an IP
packet is carried inside an Ethernet frame. That nesting is called **encapsulation**.

## Details

### Why "layers" at all
Each layer solves exactly one problem and trusts the layer below to handle the next
step down. That separation means you can change one layer without rewriting the
others (Wi-Fi vs. cable is an L2 swap; the IP layer above doesn't care). For this
note only two layers matter: **L2 = local delivery, L3 = delivery across networks.**

### L2 / Ethernet — "which machine on this street"
- **Job:** deliver to a specific machine **on the same local segment** (one LAN /
  one switch). Ethernet has no concept of "the internet" — only "put this on the
  wire for that MAC."
- **Unit:** a **frame**.
- **Address:** a **MAC address** (Media Access Control) — a 48-bit hardware address
  written like `52:54:00:ab:cd:ef`, one per network interface.
- **Who works here:** switches (and a Linux bridge, which is a software switch).

### L3 / IP — "which building in which city"
- **Job:** get data **from one network to another**, across many hops, to anywhere
  on the internet.
- **Unit:** a **packet**.
- **Address:** an **IP address** (e.g. `10.42.0.7`).
- **Who works here:** routers (and any host configured to route).

### Encapsulation — L2 carries L3
You don't pick one layer; you stack them. An IP packet is placed *inside* an
Ethernet frame as its payload:

```
┌─────────────── Ethernet frame (L2) ───────────────────────────┐
│ dst MAC │ src MAC │ type │   IP packet (L3)            │ check │
│                          │ dst IP │ src IP │ payload …  │       │
└────────────────────────────────────────────────────────────────┘
```

So every hop reads the L2 header to take the next physical step, and the L3 header
to know the ultimate destination. The MAC addresses get **rewritten at every hop**
(new street, new local addresses); the IP addresses normally stay the same end to
end (same final destination).

### The one-line mental model
- **MAC / L2** = which machine on *this* local network (the next physical hop).
- **IP / L3** = which machine on the *whole* internet (the final destination).
You need both at once: IP to know where it's ultimately going, MAC to make the next
concrete handoff.

### Jargon, glossed simply
- **Layer** — one self-contained job in the networking stack (local delivery, cross-network delivery, …).
- **Frame** — the L2 unit of data (an Ethernet "envelope").
- **Packet** — the L3 unit of data (the IP "letter" inside the envelope).
- **MAC address** — a per-network-card hardware address; used for local (L2) delivery.
- **IP address** — a logical address used for cross-network (L3) delivery.
- **Segment / LAN** — one local network where machines reach each other directly at L2.
- **Encapsulation** — wrapping a higher-layer unit inside a lower-layer one (IP packet inside an Ethernet frame).

## Key points
- Networking is layered; each layer has its own address type and job.
- L2 (Ethernet) delivers *frames* by *MAC address* within one local segment only.
- L3 (IP) delivers *packets* by *IP address* across different networks, via routers.
- A MAC address is a hardware address per NIC (e.g. 52:54:00:ab:cd:ef); an IP address is a logical address (e.g. 10.42.0.7).
- An IP packet is carried inside an Ethernet frame — this nesting is "encapsulation," so L2 carries L3.
- MAC addresses are rewritten at every hop; IP addresses normally stay the same end to end.
- Mental model: MAC = which machine on this local street; IP = which building in which city.

## References
- TCP/IP and OSI layering model (link layer vs network layer) — standard networking reference material.
- IEEE 802.3 — Ethernet (frames, 48-bit MAC addressing).
- RFC 791 — Internet Protocol (IP packets and addressing).

## Related
- [Ethernet Switching: ARP, MAC Learning, and the FDB](ethernet-switching-arp-fdb.md) — how L2 actually delivers a frame to the right machine.
- [IP Routing, Default Gateways, and ip_forward](ip-routing-and-gateways.md) — how L3 delivers a packet across networks.
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — these layers applied to VM networking.