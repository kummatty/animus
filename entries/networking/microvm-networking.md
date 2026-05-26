---
title: "MicroVM Host Networking: Bridges, TAPs, TUN, and NAT"
slug: microvm-networking
topic: networking
tags: [networking, virtualization, firecracker, bridge, tap, tun, nftables, netlink, nat, namespaces, l2]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
To give a virtual machine network access, the host has to build virtual "wiring"
because the VM has no real network card. The common, simplest design is the
**bridge model**: the host runs a **Linux bridge** (a virtual ethernet switch),
and each VM gets a **TAP device** (a virtual network card) plugged into that
switch. Because every VM hangs off one switch, the VMs share a single virtual LAN
and can talk to each other directly (**VM↔VM**) at layer 2. To reach the public
internet (**VM↔internet**), the host gives each VM a private address and uses
**NAT** to rewrite that private address to the host's real one on the way out.
Two host tools do the work: **netlink** (configures the links/addresses) and
**nftables** (the packet filter that does NAT). The bridge model is easy but puts
all VMs on one shared segment; stronger-isolation alternatives (per-VM **network
namespaces**, or a **routed/NAT** layout) trade simplicity for keeping VMs apart.

## Details

### The bridge model at a glance

```
   VM-A guest                         VM-B guest
   (eth0)                             (eth0)
     │                                   │
  ┌──┴───┐  host-side virtual NICs    ┌──┴───┐
  │ tap0 │                            │ tap1 │
  └──┬───┘                            └──┬───┘
     └──────────────┬───────────────────┘
              ┌──────┴───────┐  Linux bridge = in-kernel L2 switch
              │     br0       │  (also has the host's IP, e.g. 10.0.0.1)
              └──────┬────────┘
                     │  host routes + NAT (nftables)
                  ┌──┴──┐
                  │ eth0│ ── physical uplink ── internet
                  └─────┘
```

- **VM↔VM** stays inside the bridge: pure L2 frame switching, never touches the
  host's IP routing or the uplink.
- **VM↔internet** goes up through the host's IP stack, gets NAT'd, and out `eth0`.

### Layer 2, frames, and the Linux bridge

Networking is layered. **L2 (the data-link layer, i.e. Ethernet)** moves *frames*
between devices **on the same local segment**, addressed by **MAC address** (a
48-bit hardware address like `52:54:00:ab:cd:ef`). **L3 (IP)** moves *packets*
across *different* networks, addressed by IP, and is what routers handle. An IP
packet rides *inside* an Ethernet frame: `[dst MAC | src MAC | ethertype | IP
packet | CRC]`. So L2 carries L3.

A **Linux bridge** is a **virtual L2 switch implemented in the kernel**. Each TAP
attached to it is a "port." It is self-configuring via **MAC learning**: for every
frame, it records `source MAC → the port it arrived on` in a **forwarding database
(FDB)**, then forwards by destination MAC —

- **known unicast** → send only out the one port the dst MAC was learned on;
- **unknown unicast / broadcast** (e.g. ARP) → **flood** out every port except the
  one it arrived on (the reply then teaches the bridge where that MAC lives);
- FDB entries **age out** after idle (~5 minutes / 300 s by default), so stale
  mappings are forgotten.

You also normally **assign the bridge an IP** (e.g. `10.0.0.1/24`). That does two
jobs at once: it puts the *host* on the VM LAN (so the host can reach a VM directly,
e.g. `curl 10.0.0.7`), and it makes the bridge the VMs' **default gateway** out to
the internet. Operational gotcha: a bridge with no explicit MAC adopts the *lowest*
MAC among its ports, so attaching the first TAP can flip the bridge's MAC and blip
the host IP — pin a fixed locally-administered MAC (`02:..`) at creation to avoid it.

### TAP, TUN, and the tun driver

A **TAP device** is a *virtual network card*: one end is a normal host interface
(e.g. `tap0`), the other end is a **file descriptor held by a userspace program**.
Whatever the kernel "transmits" out that interface becomes readable on the fd, and
whatever the program writes to the fd is injected as if it arrived on that
interface. For a VM, the **VMM (e.g. Firecracker) holds the fd**, and the guest
sees a normal NIC; the host side is just a bridge port.

The same kernel driver — the **tun driver**, exposed as the character device
`/dev/net/tun` — makes two flavors:

- **TUN** (`IFF_TUN`, `0x0001`): carries **L3 IP packets**, no ethernet header, no MAC.
- **TAP** (`IFF_TAP`, `0x0002`): carries **L2 ethernet frames**, has a MAC, acts like a real NIC.

"tun" is both the *driver name* and one of its two *modes*; you want **TAP** for a
bridge, because the bridge needs ethernet frames. A TUN device can't attach to a
bridge.

**What a "flag" even is, and who reads it.** When a program creates a tun/tap device
(via the `TUNSETIFF` request to `/dev/net/tun`), it must tell the kernel *how* it
wants the device set up: which mode, whether to prepend metadata, and so on. Rather
than pass a dozen separate booleans, these on/off choices are packed into **one
integer as bit flags** — each option owns a single bit, named by a constant
(`IFF_TAP = 0x0002`, `IFF_NO_PI = 0x1000`, …). You turn on the ones you want by
OR-ing them together (`IFF_TAP | IFF_NO_PI` = one integer with both bits set), and
the **kernel's tun driver reads that bitfield**, testing each bit with a bitwise AND
(`flags & IFF_TAP`), to decide what kind of device to build and how it behaves. So a
"flag" is just one named yes/no switch living inside that single number, and
"setting a flag" means turning its bit on. In short: the flags *flag your
configuration choices to the kernel at creation time* (and some stay attached to the
device afterward, governing how reads/writes on the fd are framed). Same pattern
shows up all over systems programming — `open()` flags, `mmap()` protections, etc.

**The flags themselves (the ones that confuse people):**

- **`IFF_TUN` / `IFF_TAP`** — pick the mode (L3 vs L2); exactly one.
- **`IFF_NO_PI`** (`0x1000`) — "no packet information." *Without* it, the driver
  prepends a 4-byte header (`struct tun_pi { u16 flags; u16 proto; }`) to every
  packet on the fd. *With* it, the fd carries the raw frame, nothing prepended.
  VM taps want `IFF_TAP | IFF_NO_PI` so frames aren't corrupted by a stray header.
- **`IFF_VNET_HDR`** — prepend a *different* header (`virtio_net_hdr`) carrying
  offload hints (segmentation/checksum) for performance; VMMs negotiate this.
- **`IFF_MULTI_QUEUE`** — allow several fds/queues on one device for SMP scaling.

**Persistence & ownership** (set via separate requests, not flags): by default a
tun/tap device vanishes when its creating fd closes. The `TUNSETPERSIST` request
makes it outlive the fd, so the host can **pre-create a named tap and let the VMM
open it later by name** (Firecracker's `host_dev_name`). `TUNSETOWNER`/`TUNSETGROUP`
let an **unprivileged** VMM open it.

### VM ↔ VM communication

This is *just the bridge doing its job*. Frame from VM-A → `tap0` → `br0`; the
bridge looks up VM-B's MAC and switches the frame straight out `tap1` → VM-B. It
**never touches the host's IP stack, NAT, or the uplink** — pure L2, host-internal,
fast. All VMs are effectively on one flat ethernet segment, talking as neighbors.
(Consequence: in the plain bridge model VMs are *not* isolated from each other — see
Alternatives.)

### VM ↔ Internet communication (NAT)

VMs use **private addresses** (RFC 1918 ranges like `10.x`, `192.168.x`) that are
**not routable on the public internet** — no router out there can send a reply back
to `10.0.0.7`. So when a VM packet leaves the host, the kernel rewrites the **source
IP** to the host's real IP; replies come back to the host, which reverses the
mapping (via connection tracking) and delivers to the VM. That source-rewrite is
**NAT (Network Address Translation)**; the "use whatever IP the outbound interface
has" flavor is **masquerade** — exactly what a home router does.

Three things must all be true or VM egress silently fails:

1. **A masquerade rule** on the host (nftables, below).
2. **`net.ipv4.ip_forward = 1`** — the sysctl is *off by default* ("I'm a host, not
   a router"); without it the kernel drops packets it would forward between the
   bridge and the uplink.
3. **The netfilter `forward` hook must permit it.** On a clean host the default is
   accept, but **Docker and firewalld install a `forward` chain with a `drop`
   policy**, which black-holes VM traffic even though NAT and `ip_forward` look
   correct. You add your own accept rule (and must detect a foreign force-drop
   rather than silently fail).

The VM's **default gateway** is the bridge's IP; the host routes from there to the
uplink and masquerades.

### The two host tools: netlink and nftables

- **netlink** is the kernel's socket-based configuration interface (`AF_NETLINK`).
  Its *route* family configures **links, addresses, routes, neighbors** — it's what
  `ip` uses under the hood, and the modern replacement for the old `ioctl`-based
  (`SIOCxxx`) network config. Creating the bridge, addressing it, creating/enslaving
  TAPs, bringing links up — all netlink.
- **nftables** is the modern Linux packet filter (replacement for `iptables`). NAT
  lives here: a `nat`-type chain on the `postrouting` hook with a `masquerade` rule,
  plus a `filter`-type chain on the `forward` hook for the accept rules.
- **Subtlety:** these are *different kernel subsystems* reached over *different*
  netlink families — route-netlink can't express NAT, and netfilter is its own thing.
  And **TAP creation specifically is neither**: it's an `ioctl` on `/dev/net/tun`
  (the tun driver). A newer route-netlink path can create a `tun`-kind link
  (kernel ≥ 5.7), but the classic `/dev/net/tun` + `ioctl` path is the standard,
  fuller-featured way (it also hands you the fd and lets you set the flags/owner directly).

### Worked example: full setup with `ip` + `nft`

Host-wide, once (bridge `br0` at `10.0.0.1/24`, uplink `eth0`):

```bash
# bridge (the virtual L2 switch) + host's address on the VM LAN / gateway
ip link add br0 type bridge
ip addr add 10.0.0.1/24 dev br0
ip link set br0 up

# let the kernel forward, and NAT VM traffic out the uplink
sysctl -w net.ipv4.ip_forward=1
nft add table ip nat
nft add chain ip nat postrouting '{ type nat hook postrouting priority srcnat ; }'
nft add rule ip nat postrouting ip saddr 10.0.0.0/24 oifname "eth0" masquerade
```

Per VM, at launch:

```bash
ip tuntap add tap0 mode tap user someuser   # persistent, owned tap (ioctl under the hood)
ip link set tap0 master br0                  # plug it into the bridge
ip link set tap0 up
# then hand "tap0" to the VMM (e.g. Firecracker host_dev_name); the guest gets an
# IP in 10.0.0.0/24 (static, or DHCP via dnsmasq on br0) with gateway 10.0.0.1
```

VM↔VM now works via `br0` (L2). VM↔internet works via the gateway → forward → NAT.

### Alternatives (trade simplicity for isolation)

The plain bridge model is simplest but puts **all VMs on one L2 segment** — they
can see/reach each other, and a noisy or hostile VM shares the broadcast domain.
When you need VMs isolated from *each other*, two common alternatives:

- **Per-VM network namespaces (+ veth).** Each VM's tap lives in its **own network
  namespace** (an isolated copy of the network stack), connected to the host by a
  **veth pair** (a virtual cable with one end in the namespace, one on the host).
  VMs can't see each other's L2 traffic; VM↔VM (if allowed) goes through host
  routing, not a shared switch. This is the model Firecracker recommends for
  production isolation (its **jailer** can place each microVM in its own netns).
  Stronger isolation, more moving parts.
- **Routed / NAT layout (no bridge).** Instead of switching, give each tap its own
  tiny subnet (e.g. a `/30` or `/31`) or a `/32` host route, and have the host
  **route** (L3) between taps and the uplink, NATing as needed. No shared L2 segment,
  so VMs are isolated by default; VM↔VM traffic is routed by the host. (This is the
  "assign an IP to the tap, enable forwarding + NAT, skip the bridge" approach shown
  in Firecracker's networking examples.)

Rule of thumb: **bridge = shared LAN, simplest, VMs can talk freely; namespaces /
routed = isolation between VMs, at the cost of complexity.** Pick based on whether
VM-to-VM isolation actually matters for your workload.

## Key points
- L2/Ethernet moves *frames* by MAC address on one local segment; L3/IP moves
  *packets* by IP across networks. An IP packet rides inside an Ethernet frame.
- A Linux bridge is an in-kernel virtual L2 switch; each attached TAP is a port.
- A bridge self-learns: it records source-MAC→port in a forwarding database (FDB),
  forwards known unicast to one port, and floods unknown-unicast/broadcast to all
  other ports; FDB entries age out (~300 s default).
- Giving the bridge an IP puts the host on the VM LAN (host can reach VMs directly)
  and makes the bridge the VMs' default gateway.
- A bridge with no explicit MAC adopts the lowest MAC among its ports, so attaching
  the first TAP can flip its MAC; pin a fixed `02:..` MAC at creation.
- A TAP device is a virtual NIC whose far end is a userspace file descriptor; the
  VMM holds the fd and the guest sees a normal network card.
- TUN = L3 (IP packets, no MAC); TAP = L2 (ethernet frames, has a MAC). The bridge
  needs TAP; a TUN can't attach to a bridge.
- One kernel "tun driver" (`/dev/net/tun`) provides both modes; "tun" is both the
  driver name and one of its two modes.
- A "flag" is a single named bit in an integer; device options are packed as bit
  flags (IFF_TAP=0x0002, IFF_NO_PI=0x1000, …), combined with bitwise OR, and read by
  the kernel's tun driver at creation (via bitwise AND) to configure the device.
- Without IFF_NO_PI the tun driver prepends a 4-byte `tun_pi` header (flags+proto)
  to every packet on the fd; VM taps use IFF_TAP|IFF_NO_PI to carry raw frames.
- IFF_VNET_HDR adds a virtio offload header (for segmentation/checksum perf);
  IFF_MULTI_QUEUE allows multiple fds/queues per device.
- TUNSETPERSIST makes a tap outlive its creating fd, so the host can pre-create it
  and the VMM opens it by name; TUNSETOWNER/GROUP let an unprivileged VMM open it.
- VM↔VM traffic is pure L2 switching through the bridge — it never touches the
  host's IP routing, NAT, or the physical uplink.
- VMs use private (RFC 1918) addresses that aren't internet-routable, so the host
  NATs/masquerades the source IP to its own for VM↔internet traffic.
- VM internet egress needs three things: a masquerade rule, `net.ipv4.ip_forward=1`
  (off by default), and the netfilter `forward` hook permitting it.
- Docker/firewalld install a `forward` chain with a drop policy that silently
  black-holes VM egress even when NAT and ip_forward are correct.
- netlink (AF_NETLINK, route family) configures links/addresses/routes and is the
  modern replacement for ioctl-based (SIOCxxx) network config; nftables (replacing
  iptables) does the NAT/forward filtering.
- TAP creation is an ioctl on /dev/net/tun (the tun driver), not route-netlink; a
  netlink path to create a tun/tap link exists since kernel 5.7 but the ioctl path
  is the standard, fuller-featured way.
- Bridge model = all VMs on one shared L2 segment (simple, VMs talk freely, no
  inter-VM isolation).
- Per-VM network namespaces + veth pairs isolate each VM's stack (Firecracker's
  jailer uses this for production isolation); VM↔VM then routes through the host.
- A routed/NAT layout drops the bridge entirely: each tap gets its own subnet/host
  route and the host routes+NATs, isolating VMs by default.

## References
- Firecracker issue #711, "Add Host Networking Setup Example" — community recipes
  using `ip tuntap add ... mode tap user ...`, bridging, and `host_dev_name`:
  https://github.com/firecracker-microvm/firecracker/issues/711 (accessed 2026-05-25)
- Cloudflare, "Virtual networking 101: Understanding TAP" — TAP/tun internals and
  the `IFF_*` flags (reader-supplied):
  https://blog.cloudflare.com/virtual-networking-101-understanding-tap/ (accessed 2026-05-25)
- Linux kernel headers `linux/if_tun.h` (IFF_TUN/IFF_TAP/IFF_NO_PI = 0x0001/0x0002/0x1000;
  tun_pi) and `linux/if_link.h` — source of the flag/constant values.

## Related
- [Isolation Models: Containers, gVisor, microVMs, and Full VMs](../virtualization/isolation-models.md) — the microVMs this networking plumbs; per-VM network namespaces tie back to the isolation spectrum there.
- [Network Layers: L2 (Ethernet) vs L3 (IP)](network-layers-l2-l3.md) — the L2/L3 foundation this setup rests on.
- [Ethernet Switching: ARP, MAC Learning, and the FDB](ethernet-switching-arp-fdb.md) — the concept behind VM↔VM bridge switching.
- [IP Routing, Default Gateways, and ip_forward](ip-routing-and-gateways.md) — how the host routes VM traffic toward the uplink.
- [Creating TAP Devices with ioctl on /dev/net/tun](tap-devices-and-ioctl.md) — the ioctl mechanism behind TAP creation.
- [Connection Tracking (conntrack) and NAT/Masquerade](conntrack-and-nat.md) — the concept behind the masquerade rule and reply handling.
- [Netfilter Hooks, nftables Rules, and the Forward Chain](netfilter-hooks-and-forward-rules.md) — the hook/chain model behind the NAT and forward rules.