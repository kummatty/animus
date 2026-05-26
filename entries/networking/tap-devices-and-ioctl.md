---
title: "Creating TAP Devices with ioctl on /dev/net/tun"
slug: tap-devices-and-ioctl
topic: networking
tags: [networking, tap, tun, ioctl, syscall, ifreq, kernel, firecracker, jargon]
created: 2026-05-25
updated: 2026-05-25
source: conversation
---

## Summary
A **TAP device** is a virtual network card whose "cable" is a **file descriptor**
held by a userspace program (such as a VM monitor). The kernel doesn't offer a normal
function to mint one, so you use **`ioctl`** — a catch-all syscall for device-specific
commands — on the special file **`/dev/net/tun`**. You open that file (getting an
unbound handle into the kernel's *tun driver*), then issue a **`TUNSETIFF`** request
describing the device you want (a name plus some flags), and the kernel **creates the
interface and binds it to your fd**. A separate request, **`TUNSETPERSIST`**, makes
the device outlive the fd, so a VM monitor can open it later **by name** and attach
its own fd. This note is about the *mechanism* (ioctl); for TUN-vs-TAP and the flag
bits themselves see the related microVM entry.

## Details

### What an `ioctl` is
`ioctl(fd, request, arg)` is the syscall for **device-specific control commands** that
don't fit `read`/`write`. `read`/`write` move a *stream of bytes*; `ioctl` issues an
*out-of-band command* to a device ("eject the disc," "set the baud rate," "make this
tun device a TAP"). Three parts:
- **`fd`** — which device.
- **`request`** — which command, encoded as a **packed integer** holding four fields:
  direction (read/write), a **"magic" type byte** (which driver — tun uses `'T'`), a
  command **number**, and the **size** of the argument. The kernel demuxes on
  (magic, number) to route the call to the right driver and handler.
- **`arg`** — either an **integer passed by value** *or* a **pointer to a struct** the
  kernel copies in.

"Writing an integer to the kernel" just means the second style: the number itself is
the whole message (e.g. `TUNSETPERSIST(1)` — `1` = "yes, persist").

### `/dev/net/tun` is a clone device
`/dev/net/tun` is a single special file that is a **clone device**: each `open()`
returns a fresh, **independent, unbound** handle into the kernel's **tun driver**.
Opening it **creates no interface yet** — it just gives you a control fd.

### `ifreq` — the argument struct
Interface-configuring ioctls share one struct, **`ifreq`** ("interface request"):
- a fixed **name** field (`ifr_name`, ≤ 15 chars) — *which* interface (or what to name
  a new one);
- a **union** holding one operation-specific value (here, the device **flags**).
You zero the whole struct, set the name, set the flags, and pass `&ifreq`. (It's a
union, so only the field the specific command expects is meaningful — the rest is
ignored.)

### `TUNSETIFF` — the moment the device is born
With `IFF_TAP` (plus `IFF_NO_PI`) in the flags, `TUNSETIFF` tells the kernel: create
a **TAP** interface of this name and **bind it to this fd**. Before this call the
interface doesn't exist; after it, `ip link` shows it and the fd is its userspace end.
(`TUNSETIFF` takes a *pointer* to the `ifreq` — the kernel copies it in.)

### Persistence and attach-by-name
By default a tun/tap device **vanishes when its creating fd closes**. `TUNSETPERSIST(1)`
(an *integer* argument) detaches the device's lifetime from the fd so it survives.
That's what lets the host **pre-create a named TAP**, drop its fd, and have a VM
monitor (e.g. Firecracker via `host_dev_name`) **open `/dev/net/tun` and `TUNSETIFF`
the same name** later to attach *its* fd. A non-multiqueue TAP allows **only one
attached fd at a time** — a second attach while the device is live returns **`EBUSY`**.
(`TUNSETOWNER`/`TUNSETGROUP` hand the device to an unprivileged monitor's uid/gid.)

### Why ioctl and not netlink
Historically `/dev/net/tun` + ioctl was the only way to make a tap, and it's still the
standard, fuller-featured path — it hands you the fd, the flags, and ownership
directly. (A route-netlink path to create a `tun`-kind link exists since kernel 5.7,
but doesn't expose all of that as cleanly.)

### Jargon, glossed simply
- **ioctl** — a syscall for device-specific commands that don't fit read/write.
- **syscall** — a request from a userspace program into the kernel.
- **file descriptor (fd)** — a small integer handle to an open file/device.
- **`/dev/net/tun`** — the special file that is the control entry point to the tun driver.
- **clone device** — a file where each `open()` yields a fresh, independent instance.
- **request code** — the packed integer naming an ioctl command (direction + magic + number + size).
- **`ifreq`** — the generic "interface request" struct: a name + a union of one value.
- **union** — overlapping storage where only one field is valid at a time.
- **`TUNSETIFF` / `TUNSETPERSIST`** — ioctl commands to create-and-bind a tap / to make it persist.
- **`EBUSY`** — error returned when attaching a second fd to a single-queue tap that's already attached.

## Key points
- A TAP device is a virtual NIC whose far end is a userspace file descriptor.
- `ioctl(fd, request, arg)` issues device-specific commands that don't fit read/write.
- The ioctl `request` is a packed integer: direction + a "magic" driver byte + command number + argument size.
- The `arg` is either an integer passed by value (e.g. TUNSETPERSIST(1)) or a pointer to a struct copied into the kernel (e.g. TUNSETIFF with ifreq).
- `/dev/net/tun` is a clone device: each open() gives a fresh unbound handle and creates no interface by itself.
- `ifreq` is the shared interface-ioctl struct: a fixed name field plus a union holding one operation-specific value (the flags).
- TUNSETIFF with IFF_TAP creates the named TAP interface and binds it to the calling fd.
- By default a tap dies when its creating fd closes; TUNSETPERSIST(1) makes it persist so a VMM can open it later by name.
- A non-multiqueue tap allows only one attached fd at a time; a second attach returns EBUSY.
- ioctl on /dev/net/tun is the standard way to make a tap (it hands you fd + flags + owner); a netlink path exists since kernel 5.7 but is less complete.

## References
- `man 2 ioctl` — the ioctl syscall (fd, request, arg).
- Linux kernel header `linux/if_tun.h` — TUNSETIFF/TUNSETPERSIST/TUNSETOWNER, IFF_* flags, the `'T'` magic.
- Linux kernel `Documentation/networking/tuntap.rst` — tun/tap driver, persistence, attach-by-name.

## Related
- [MicroVM Host Networking: Bridges, TAPs, TUN, and NAT](microvm-networking.md) — TUN vs TAP, the IFF_* flag bits, and how the VMM uses the tap.
- [Network Layers: L2 (Ethernet) vs L3 (IP)](network-layers-l2-l3.md) — a TAP is an L2 device (TUN is L3).
