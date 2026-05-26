---
title: "Connection Tracking (conntrack) and NAT/Masquerade"
slug: conntrack-and-nat
topic: networking
tags: [networking, conntrack, nat, masquerade, snat, stateful-firewall, netfilter, jargon]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
**Connection tracking** ("conntrack") is a kernel feature that remembers every active
network **conversation (flow)** and labels each passing packet with that flow's
**state** — `new`, `established`, `related`, or `invalid`. This does two big things:
it makes a firewall **stateful** (decide once when a conversation starts, then
recognize all the follow-up packets and replies automatically), and it makes **NAT
reversible**. **NAT** (Network Address Translation) rewrites addresses in packets; the
common case for private networks is **source NAT / masquerade**, which rewrites a
VM's private source IP to the host's real outgoing IP so replies can find their way
back — and conntrack is what remembers the mapping in order to undo it on the return
trip.

## Details

### Connection tracking (conntrack)
The kernel watches traffic and records each **flow** by its 5-tuple (protocol, source
IP:port, destination IP:port). It tracks not just TCP but UDP "flows" and ICMP
(e.g. ping) too. Every packet gets a **state**:
- **new** — the first packet of a flow conntrack hasn't seen before.
- **established** — a packet belonging to a flow already underway (traffic has gone
  both ways / it's ongoing).
- **related** — a *new* flow that conntrack knows was **spawned by an existing one**
  (an ICMP error about a tracked connection, or an FTP data channel).
- **invalid** — matches no known flow, or is malformed.

Why it matters: you can write one rule — "allow new connections from the trusted
side" — and let **`established,related`** wave through everything that belongs to an
already-approved conversation, **including replies**. That's a *stateful* firewall.
(Note: a flow only becomes `established`/`related` *after* a first packet was allowed
through — so those states continue approved conversations, they never open a new one.)

### NAT (Network Address Translation)
NAT rewrites the IP (and often port) in packets as they pass through a router. Flavors:
- **SNAT (source NAT)** — rewrite the **source** address. Used for outbound
  private → public traffic.
- **DNAT (destination NAT)** — rewrite the **destination** address. Used for port
  forwarding / exposing an internal service.
- **Masquerade** — a *source NAT variant* that uses **whatever IP the outgoing
  interface currently has**, chosen dynamically at send time. Handy when that IP can
  change (DHCP, a laptop, a home router). Static SNAT pins a fixed address instead.

### Why private networks need NAT (and how conntrack closes the loop)
VMs use **private (RFC 1918) addresses** — `10.x`, `192.168.x`, etc. — which are
**not routable on the public internet**: no router out there could send a reply back
to `10.42.0.7`. So on the way out, the host **masquerades** the source to its own
routable IP. Conntrack records "this flow is `10.42.0.7:p` ⇄ `host:p′`." When the
reply arrives at the host, conntrack **reverses** the translation and delivers it to
the right VM.

### Worked example
```
VM 10.42.0.7  ──► dst 8.8.8.8, src 10.42.0.7
   host masquerades:      src rewritten to host's uplink IP; conntrack stores the mapping
   leaves uplink ──►  8.8.8.8
8.8.8.8 replies  ──►  dst = host IP   (it only ever saw the host)
   host: conntrack recognizes the flow → state established → un-NAT → dst = 10.42.0.7
   delivered back to the VM
```
The reply's conntrack **state is `established`**, which is exactly what a stateful
forward rule keys on to allow it back (see related note on forward rules).

### Jargon, glossed simply
- **conntrack / connection tracking** — kernel bookkeeping of active flows and their state.
- **flow / conversation** — one tracked exchange, identified by its 5-tuple.
- **state (new/established/related/invalid)** — conntrack's label for where a packet sits in its flow.
- **stateful firewall** — one that decides per *conversation* (using state), not per isolated packet.
- **NAT** — rewriting addresses in packets as they pass through.
- **SNAT / DNAT** — rewrite source / rewrite destination.
- **masquerade** — SNAT to the outgoing interface's current IP, chosen dynamically.
- **RFC 1918 / private addresses** — IP ranges (10.x, 172.16.x, 192.168.x) not routable on the internet.

## Key points
- conntrack remembers active flows (by 5-tuple) and labels each packet new / established / related / invalid.
- It tracks TCP, UDP, and ICMP — "connection" means any tracked flow, not only TCP.
- `established` = packet of an ongoing flow; `related` = a new flow spawned by an existing one (ICMP errors, FTP data).
- A stateful firewall decides once on the `new` packet, then `established,related` admits the rest — including replies.
- `established`/`related` only exist after a first packet was already allowed, so they continue approved flows, never start new access.
- NAT rewrites addresses: SNAT (source), DNAT (destination), masquerade (SNAT to the outgoing interface's current IP).
- Private RFC 1918 addresses (10.x, 192.168.x) aren't internet-routable, so a VM's source IP must be NAT'd to the host's real IP.
- conntrack stores the NAT mapping so it can reverse it on replies and deliver them back to the right VM.

## References
- Netfilter project — connection tracking (nf_conntrack) documentation, netfilter.org.
- RFC 1918 — Address Allocation for Private Internets.
- RFC 2663 — IP Network Address Translator (NAT) terminology (SNAT/DNAT/masquerade concepts).

## Related
- [Netfilter Hooks, nftables Rules, and the Forward Chain](netfilter-hooks-and-forward-rules.md) — where `ct state` rules and the masquerade rule actually run.
- [IP Routing, Default Gateways, and ip_forward](ip-routing-and-gateways.md) — NAT happens as the host routes a VM packet toward the uplink.
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — NAT/masquerade applied to VM internet egress.
