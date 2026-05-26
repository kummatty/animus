---
title: "IP Routing, Default Gateways, and ip_forward"
slug: ip-routing-and-gateways
topic: networking
tags: [networking, ip, l3, routing, gateway, routing-table, ip-forward, jargon]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
When a machine wants to send an IP packet, it first asks: **is the destination on my
own local subnet?** If yes, it delivers directly at L2 (ARP + frame). If not, it
*can't* reach the destination itself, so it hands the packet to its **default
gateway** — a router on its local network whose job is to pass packets toward other
networks. Each router along the way repeats this, consulting a **routing table** that
maps destination ranges to "next hop / outgoing interface," forwarding the packet
**hop by hop** until it arrives. A Linux host will only *forward* packets between its
interfaces (act as a router) if the **`ip_forward`** switch is turned on — by default
it's off, because a normal host is an endpoint, not a router.

## Details

### Step 1: local or remote? (the subnet test)
Every interface has an IP and a **subnet mask** (e.g. `10.42.0.7/16`). To send to a
destination IP, the machine checks whether it falls inside its own subnet:
- **Local** (same subnet): reach it directly — ARP for its MAC, send the frame. Done.
- **Remote** (different subnet): "I can't reach that directly." Send it to the
  **default gateway** instead.

### Step 2: the default gateway
The default gateway is just a regular neighbor on your LAN (a router) that you've
been told to hand "everything not local" to. You ARP for the *gateway's* MAC and send
the frame there; the gateway takes it from your network toward the rest of the world.
Its IP is part of your config (e.g. a VM's gateway is the bridge IP `10.42.0.1`).

### Step 3: routers and the routing table
A router decides where to send each packet using a **routing table** — a list of
"destination-range → next hop, out which interface," matched by **longest prefix**
(most specific wins), with a catch-all `default` route:

```
default        via 192.168.1.1   dev eth0     # everything else → upstream router, out eth0
10.42.0.0/16                      dev rig0      # the VM subnet, directly attached here
192.168.1.0/24                    dev eth0      # the LAN this host sits on
```

A packet for `8.8.8.8` matches none of the specific routes → falls to `default` →
"send via `192.168.1.1`, out `eth0`."

### Step 4: hop by hop, and "two gateways"
No single device knows the whole path — each only knows its **next hop**. The packet
is forwarded router to router until it arrives. In a VM setup this stacks:
- the **VM's** gateway is the host (e.g. `10.42.0.1`) — how the VM leaves its network;
- the **host's** gateway is the upstream router (e.g. `192.168.1.1`) — how the host
  leaves *its* network.
The VM hands the packet to the host; the host hands it to its own upstream gateway;
and so on.

### Step 5: ip_forward — host as endpoint vs. router
By default, a Linux host that receives a packet **not addressed to itself** simply
**drops** it ("I'm a host, not a router"). Setting `net.ipv4.ip_forward = 1` flips it
into a router that will forward packets between its interfaces:
```
ip_forward = 0:  packet for 8.8.8.8 arrives → "not for me, I'm not a router" → DROP
ip_forward = 1:  packet for 8.8.8.8 arrives → consult routing table → forward out eth0
```
This is the prerequisite for a host to relay VM traffic to the internet at all.

### Jargon, glossed simply
- **Subnet / subnet mask / CIDR (`/16`)** — defines which IP range counts as "local"; used for the local-vs-remote test.
- **Default gateway** — the router you send all non-local packets to; a normal neighbor on your LAN.
- **Routing table** — the rules mapping destination ranges to "next hop + outgoing interface."
- **Next hop** — the very next router to hand the packet to (not the final destination).
- **Hop** — one router-to-router handoff along the path.
- **Longest-prefix match** — when several routes match, the most specific one wins.
- **ip_forward** — the Linux switch that turns a host into a router (off by default).

## Key points
- A sender first tests destination vs. its own subnet: local → deliver directly (L2); remote → send to the default gateway.
- The default gateway is a router on the local network that forwards non-local packets onward; it's a regular LAN neighbor.
- Routers forward using a routing table (destination-range → next hop + interface), choosing the longest-prefix (most specific) match.
- `default` is the catch-all route used when no specific route matches (e.g. for 8.8.8.8).
- Routing is hop by hop: each device knows only its next hop, not the whole path.
- Setups stack gateways: the VM's gateway is the host; the host's gateway is its own upstream router.
- A Linux host drops packets not addressed to itself unless `net.ipv4.ip_forward=1`, which makes it act as a router.
- The bridge does not route; it just delivers the frame to the host, and the host's routing table makes the L3 decision.

## References
- RFC 791 — Internet Protocol (routing/forwarding model).
- `man 8 ip-route` — Linux routing table semantics (longest-prefix match, `default`).
- Linux kernel networking sysctls — `net.ipv4.ip_forward` (off by default).

## Related
- [Network Layers: L2 (Ethernet) vs L3 (IP)](network-layers-l2-l3.md) — why "remote" destinations need L3 routing.
- [Ethernet Switching: ARP, MAC Learning, and the FDB](ethernet-switching-arp-fdb.md) — what "deliver directly" means for a local destination.
- [Connection Tracking (conntrack) and NAT/Masquerade](conntrack-and-nat.md) — what the host does to a VM packet as it routes it out.
- [Netfilter Hooks, nftables Rules, and the Forward Chain](netfilter-hooks-and-forward-rules.md) — where forwarding is permitted or filtered.
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — the bridge IP as the VMs' gateway.
