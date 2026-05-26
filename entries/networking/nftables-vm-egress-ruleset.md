---
title: "Worked Example: nftables Ruleset for VM Internet Egress (NAT + Forward)"
slug: nftables-vm-egress-ruleset
topic: networking
tags: [networking, nftables, nat, masquerade, forward, conntrack, example, firewall, ip-forward]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
A complete, annotated **nftables ruleset** that gives bridged VMs internet access —
the readable `nft list ruleset` form of what a tool builds programmatically. It's one
**table** (`ip rig`) with two **base chains**: a **postrouting NAT chain** whose
single **masquerade** rule rewrites each VM's private source IP on the way out, and a
**forward filter chain** whose **stateful accept** rules let VM traffic (and its
replies) be routed *through* the host. The ruleset alone isn't enough — the kernel
also needs **`net.ipv4.ip_forward = 1`** so it will route between the bridge and the
uplink at all.

## Details

### Prerequisite (not part of nftables)
```bash
sysctl -w net.ipv4.ip_forward=1     # let the host route between interfaces (off by default)
```

### The full ruleset, annotated
For a bridge `rig0`, VM subnet `10.42.0.0/16`:

```
table ip rig {                       # a table = namespace in the ip (IPv4) family

	chain postrouting {              # base chain: NAT, after routing, just before egress
		type nat hook postrouting priority srcnat; policy accept;
		#                          ^ priority srcnat = 100 ; policy = pass through if no match
		ip saddr 10.42.0.0/16 oifname != "rig0" masquerade
		# IF source is a VM  AND  leaving via something other than the bridge
		# THEN masquerade: rewrite src IP to the outgoing interface's address
	}

	chain forward {                  # base chain: filter, on packets routed THROUGH the host
		type filter hook forward priority filter; policy accept;
		#                          ^ priority filter = 0
		ct state established,related accept
		# accept packets of an already-open conversation + its replies (return traffic!)
		iifname "rig0" accept
		# accept NEW outbound flows coming FROM the VM side
		oifname "rig0" accept
		# accept traffic heading TO the VM side
	}
}
```

### Reading each rule
- **`ip saddr 10.42.0.0/16`** — match packets whose IPv4 source is in the VM subnet
  ("is this from a VM?").
- **`oifname != "rig0"`** — and whose output interface is *not* the bridge ("is it
  leaving to the outside, not staying on the VM LAN?"). Written as `!= rig0` rather
  than `== eth0` so it works regardless of the uplink's name.
- **`masquerade`** — the action: source-NAT to the outgoing interface's current IP, so
  replies can route back to the host (conntrack then reverses it to the VM).
- **`ct state established,related accept`** — the stateful rule that admits return
  traffic: a reply from the internet arrives on the uplink (not `rig0`), so the
  `iifname` rule won't match it, but conntrack marks it `established` and this accepts
  it.
- **`iifname "rig0" accept` / `oifname "rig0" accept`** — allow new VM-originated flows
  out, and traffic toward the VMs.

### What it actually does: one packet's round trip
Follow VM `10.42.0.7` loading a page from the internet, and watch which rule fires:

```
OUTBOUND  (VM → internet)
1. VM sends to its gateway's MAC (rig0); the bridge hands the frame UP to the host IP stack.
2. Routing: destination isn't local → "forward" path.  (ip_forward MUST be on, or dropped here.)
3. forward hook → iif=rig0, oif=eth0 → matches `iifname "rig0" accept`.   ✓  (conntrack: NEW)
4. postrouting hook → saddr ∈ 10.42.0.0/16 AND oif=eth0 (≠ rig0) → `masquerade`:
   source rewritten 10.42.0.7 → host's uplink IP.  conntrack STORES the mapping.
5. leaves eth0 toward the server.

RETURN  (internet → VM)
6. reply arrives on eth0, addressed to the host's uplink IP (the server only ever saw the host).
7. conntrack recognizes the flow; routing sends it toward the VM → "forward" path (iif=eth0, oif=rig0).
8. forward hook → it did NOT come from rig0, so `iifname "rig0"` does NOT match —
   but `ct state established,related accept` matches.   ✓  (this is why that rule exists)
9. postrouting → conntrack REVERSES the NAT: destination → 10.42.0.7.
10. delivered down rig0 → bridge → tap → the VM.
```

The takeaway: the **outbound** packet is allowed by `iifname rig0` and NAT'd by
`masquerade`; the **return** packet can't match `iifname rig0` (it came from the
uplink), so `ct state established,related` is the rule that lets it home. Remove that
one rule and (under a drop policy) VMs could talk *out* but nothing could come *back*.

### Subtlety: `oifname`/`iifname` here are the bridge, never a TAP
At the IP layer the bridge `rig0` is a **single interface** — the individual TAP ports
(`tap-A`, `tap-B`) don't appear as `iifname`/`oifname` in the forward/postrouting
hooks. So `oifname != "rig0"` cleanly means "leaving the VM network." And **VM↔VM
same-subnet traffic never reaches these rules at all**: it's switched at L2 by the
bridge and never enters the IP forward/postrouting hooks, so neither the masquerade
nor the forward rules ever see it.

### How it maps to "three things must be true" for egress
1. **masquerade rule** → the `postrouting` chain above.
2. **`ip_forward=1`** → the sysctl above.
3. **forward hook permits it** → the `forward` chain above (and you must not be
   black-holed by another table's `forward` chain with a `drop` policy).

### Note on policy
Here both chains are `policy accept`, so the `forward` accept rules are mostly intent
— traffic flows regardless. They become the real allow-list the moment you switch to
`policy drop` (default-deny), at which point `ct state established,related accept` is
what keeps replies flowing.

### Applying and viewing
```bash
nft -f rig.nft            # apply a ruleset file (atomically)
nft list ruleset          # view the live ruleset (text form shown above)
nft -j list ruleset       # same, as JSON — the form tools serialize/parse
```
Tools (e.g. the Rust `nftables` crate) build this as a JSON object tree and pipe it to
`nft -j -f -`; `nft list ruleset` is just the human-readable rendering of the same
state.

## Key points
- The ruleset is one `ip rig` table with two base chains: `postrouting` (nat) and `forward` (filter).
- `priority srcnat` = 100 (source-NAT spot) and `priority filter` = 0 are the standard netfilter priority names shown by nft.
- The masquerade rule `ip saddr 10.42.0.0/16 oifname != "rig0" masquerade` rewrites a VM's source IP only when leaving via a non-bridge interface.
- `oifname != "rig0"` is used instead of naming the uplink, so it's robust to whatever the external interface is called.
- `ct state established,related accept` admits return traffic, because replies arrive on the uplink (not rig0) and wouldn't match the iifname rule.
- VM internet egress needs all three: the masquerade rule, `net.ipv4.ip_forward=1`, and a forward hook that permits it (no foreign drop).
- With `policy accept` the forward accepts are intent/scaffolding; with `policy drop` they become the actual allow-list.
- On the round trip, the outbound packet is allowed by `iifname rig0` and NAT'd by masquerade; the return packet can't match `iifname rig0` (it arrives on the uplink), so `ct state established` is what admits it.
- At L3 the bridge is one interface, so iifname/oifname are `rig0` or the uplink — never a TAP; VM↔VM same-subnet traffic is L2-switched and never reaches these rules.
- `nft -f` applies a ruleset; `nft list ruleset` shows it as text; `nft -j list ruleset` shows the JSON that tools serialize/parse.

## References
- `man 8 nft` — nftables ruleset syntax, `nft -f`, `list ruleset`, `-j` JSON.
- Netfilter standard hook priorities — `srcnat` = 100 (`NF_IP_PRI_NAT_SRC`), `filter` = 0 (`NF_IP_PRI_FILTER`).
- libnftables JSON format (`libnftables-json(5)`) — the JSON object tree tools build.

## Related
- [Netfilter Hooks, nftables Rules, and the Forward Chain](netfilter-hooks-and-forward-rules.md) — the concepts (hooks, chains, statements) behind this ruleset.
- [Connection Tracking (conntrack) and NAT/Masquerade](conntrack-and-nat.md) — what `masquerade` and `ct state` mean.
- [IP Routing, Default Gateways, and ip_forward](ip-routing-and-gateways.md) — why `ip_forward` is required.
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — the full applied setup this ruleset is part of.
