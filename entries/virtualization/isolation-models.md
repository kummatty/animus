---
title: "Isolation Models: Containers, gVisor, microVMs, and Full VMs"
slug: isolation-models
topic: virtualization
tags: [virtualization, sandboxing, security, firecracker, gvisor, kvm, containers, gpu]
created: 2026-05-23
updated: 2026-05-23
source: conversation
---

## Summary
When you run untrusted or semi-trusted code (e.g. an AI agent's actions, or RL
training rollouts), you put a wall around it so a bug or escape can't reach the
host. There's a spectrum of walls, from thin to thick: plain **containers** (share
the host kernel), **gVisor** (a fake kernel in software), **microVMs** like
Firecracker (a real but stripped-down virtual machine), and **full VMs** (a complete
virtual machine with virtual firmware and hardware). Thinner walls are faster and
pack more sandboxes per machine; thicker walls isolate harder and can expose real
hardware (like GPUs) but cost more memory and boot time. There is no "best" — you
pick the point on the spectrum that matches how much you trust the code and what
hardware/features you need.

## Details

### The spectrum (thin/fast → thick/strong)

```
containers (runc)  →  gVisor (runsc)   →  microVMs (Firecracker)  →  full VMs (QEMU+UEFI)
shared host kernel     fake kernel in       real guest kernel,         real guest kernel,
namespace isolation    software (Sentry)    minimal virtual hardware   full virtual hardware
~10ms start            ~10–50ms start       ~125–300ms start           seconds to start
weakest boundary       software boundary     hardware (KVM) boundary    hardware (KVM) boundary
                                            no GPU/secure-boot/nesting   GPU, secure boot, nesting
```

Key intuition: **the further right, the stronger the wall and the more real
hardware you can expose — but the heavier and slower each sandbox is.**

### Jargon glossary (read this first)

- **Hypervisor / VMM (Virtual Machine Monitor):** the program that creates and runs
  virtual machines. It pretends to be a whole computer so a guest operating system
  can boot inside it. Examples: QEMU, Firecracker, Cloud Hypervisor, VMware, Hyper-V.
- **KVM (Kernel-based Virtual Machine):** a feature *built into the Linux kernel*
  that lets a VMM use the CPU's hardware virtualization extensions (Intel VT-x /
  AMD-V) to run guest code directly on the real CPU, safely walled off. KVM is the
  reason VMs on Linux are fast instead of emulated. **KVM only exists on Linux** —
  this is why Firecracker and other KVM-based tools can't run natively on macOS or
  Windows (those use their own hypervisors: Apple's Virtualization.framework, and
  Hyper-V respectively).
- **Guest vs host:** the *host* is the physical machine + its OS; a *guest* is the
  OS running inside a VM on top of it.
- **Sentry:** the core of gVisor. It's an "application kernel" written in Go that
  runs in normal user space and *pretends to be the Linux kernel* for the sandboxed
  program. When the program makes a system call (e.g. "open this file"), the Sentry
  intercepts it and handles it itself instead of letting it hit the real host kernel.
  That indirection is gVisor's wall.
- **System call (syscall):** how a program asks the kernel to do anything privileged
  — open a file, send a network packet, allocate memory. Sandboxes work by
  controlling what syscalls can do.
- **systrap:** gVisor's default *platform* — the mechanism the Sentry uses to trap
  the sandboxed program's syscalls and redirect them to itself, entirely in user
  space, **without needing KVM**. (It replaced an older, slower mechanism called
  `ptrace`.) gVisor also has an optional **KVM platform** that uses hardware
  virtualization for a stronger CPU/memory boundary, but then it needs KVM and loses
  the "runs anywhere" benefit.
- **virtio:** a standard for *paravirtualized* devices — simplified virtual disk,
  network, etc. designed for VMs. The guest talks to a thin virtio interface instead
  of a faithfully-emulated real device. Firecracker exposes only virtio devices,
  which is why it's small and fast but can't do GPU passthrough.
- **OCI image:** the standard container image format (what `docker pull` fetches,
  e.g. `python:3.12`). gVisor and containers consume these natively; Firecracker
  does not — it wants a Linux kernel + a root filesystem image, so you need a
  pipeline to convert an image into a bootable rootfs.
- **cgroups / seccomp:** Linux kernel features for limiting a process's resources
  (cgroups: CPU/memory/disk caps) and restricting which syscalls it may make
  (seccomp). Used to fence sandboxes regardless of which model you pick.

### The four models in detail

**Containers (e.g. `runc`)** — the sandboxed processes run on the *host's own
kernel*, isolated only by Linux namespaces (separate views of processes, network,
filesystem) and cgroups. Cheapest and fastest, but the shared kernel is one bug away
from a full escape. Fine for trusted code, risky for untrusted code.

**gVisor (`runsc`)** — Google's sandbox. Instead of sharing the host kernel, each
sandbox gets the **Sentry** (the Go "fake kernel") that services its syscalls in user
space, so the guest program almost never touches the real host kernel directly.
Runs in user space via **systrap** — *no KVM required*, so it works even inside other
VMs and on hosts without hardware virtualization. Consumes OCI images natively.
Trade-offs: the wall is *software-enforced* (a large Go codebase is itself attack
surface, and the host kernel is still reachable through the restricted set of
syscalls the Sentry makes), and intercepting every syscall adds overhead, plus some
syscalls are unimplemented so not all software runs. **Linux-only.**

**microVMs (Firecracker, also Cloud Hypervisor in this class)** — a *real* virtual
machine with its own guest Linux kernel, but with the virtual hardware stripped down
to the minimum (just virtio devices, no legacy hardware, no firmware). Boots in
~125–300ms and uses little memory, so you can run thousands per host. The wall is
**hardware-enforced via KVM** — to escape you must exploit the tiny virtio device
surface or the hypervisor itself, a much narrower and stronger boundary than gVisor.
Firecracker's codebase is deliberately small (~50k lines of Rust) to keep that
surface tiny. Supports **snapshot/restore**: boot a base VM once, snapshot it, then
restore identical clones in ~tens of milliseconds (faster than cold boot) — excellent
for "reset to a known state thousands of times." Powers AWS Lambda and Fargate.
Trade-offs: needs KVM (**Linux-only**); no GPU passthrough, no secure boot, no nested
virtualization (see below); and you must build a rootfs rather than use OCI images
directly.

**Cloud Hypervisor** — same microVM idea, also Rust, but a richer device model than
Firecracker. Notably it *does* support PCIe device passthrough (including GPUs) via
VFIO, so it sits between Firecracker and a full VM. Heavier than Firecracker, lighter
than QEMU.

**Full VMs (e.g. QEMU + KVM with UEFI firmware)** — a complete virtual machine:
virtual firmware (UEFI), a full device model, and the ability to pass real hardware
through. Strongest isolation *and* highest hardware fidelity, at the cost of seconds
to boot and gigabytes of RAM per VM. This is what's needed for secure boot, FIPS,
GPU passthrough, and running other VMs *inside* the VM. (The product StereOS bets
entirely on this model for enterprise/bare-metal agent isolation.)

### Feature trade-offs (what the buzzwords mean and who can do them)

- **Secure Boot** — a firmware feature that cryptographically verifies the boot chain
  (firmware → bootloader → kernel are all signed) so nothing tampered-with can boot.
  Requires **UEFI firmware** (the open-source implementation is **OVMF/edk2**).
  MicroVMs skip firmware entirely (they load the kernel directly to boot fast), so
  they **can't** do secure boot. Full VMs with OVMF **can**.
- **FIPS (FIPS 140-2/140-3)** — a US government standard certifying cryptographic
  modules (the validated crypto library/OS build an org is *required* to use in
  regulated/government settings). In practice you need to boot a full, certified OS
  with its proper boot chain — easy in a **full VM**, awkward in a stripped microVM.
  Primarily an enterprise/compliance concern.
- **GPU passthrough** — giving a sandbox direct access to a physical GPU so it runs
  the real driver at full speed (for training/serving local models via vLLM, Ollama,
  etc.). Done with **VFIO** (a Linux mechanism to hand a PCI device to a VM) plus an
  **IOMMU** (I/O Memory Management Unit — hardware that confines what addresses a
  passed-through device can touch, making it safe). Needs PCI support, so:
  **Firecracker: no. gVisor: only NVIDIA, via a proxy called `nvproxy` that forwards
  GPU driver calls and widens the trust boundary. Cloud Hypervisor / full VMs: yes,
  via VFIO.**
- **Nested virtualization** — running a hypervisor/VM *inside* a VM (e.g. an agent's
  sandbox itself spins up Docker-in-a-VM or Kubernetes or more VMs). Needs the CPU's
  virtualization extensions to be re-exposed to the guest. **Full VMs** can do it;
  microVMs and gVisor effectively can't. This is the technical reason you can't
  reliably run Firecracker *inside* a Mac/Windows Linux VM (you'd need nested KVM,
  which is fragile and often unavailable).

### Cross-platform reality (important and counter-intuitive)

**Real OS-level isolation is inherently Linux.** gVisor, Firecracker, Cloud
Hypervisor, KVM — all Linux-only. None run natively on macOS or Windows. The way
every cross-platform tool (Docker Desktop, Podman, Lima, OrbStack) handles this is to
quietly run a **lightweight Linux VM** on the Mac/Windows host (via Apple's
Virtualization.framework, or WSL2/Hyper-V) and run the sandboxes *inside* that Linux
VM. So "supports all machines" really means: the *client* runs everywhere, but
*isolated execution always lands on Linux*. gVisor fits this nesting cleanly because
its systrap platform needs no KVM; Firecracker fits poorly because it would need
nested KVM inside that Linux VM.

The only thing that's genuinely sandboxed natively on every OS and CPU is a **WASM**
(WebAssembly) runtime — but it can only run code compiled to WASM, not arbitrary
Linux binaries / `pip install` / general shell, so it's usually too restrictive for
general agentic execution.

### Choosing (rule of thumb)

- Trusted code, max density/speed → **containers**.
- Untrusted code, must run anywhere incl. without KVM, OCI images, density over
  boundary strength → **gVisor**.
- Strong hardware-enforced boundary, fast clones via snapshots, CPU/mem/storage
  workloads, willing to be Linux+KVM only → **Firecracker** (microVM).
- Want microVM isolation *plus* GPU passthrough → **Cloud Hypervisor**.
- Need secure boot / FIPS / GPU / nested Docker-or-k8s / bare-metal enterprise →
  **full VM**.
- Want VM-strength walls *and* standard OCI images *and* containerd integration →
  **Kata Containers**, which runs each OCI container inside a lightweight VM
  (Firecracker/Cloud Hypervisor/QEMU backend) — the "containers with VM walls" middle
  path.

### Worked example: why an RL training loop wants a *strong* but *light* sandbox

In reinforcement learning the policy is optimized to maximize reward *by any means*.
If the sandbox boundary is escapable, the policy can learn to break out and tamper
with the reward computation itself — corrupting the training signal, not just the
host. That argues for a **hardware-enforced** boundary (microVM), not just a software
one (gVisor). But RL also runs huge numbers of short rollouts, so you also need fast
**cold start** and cheap **reset-to-identical-state** — which is exactly Firecracker's
snapshot/restore. The GPU stays with the *trainer* (the model doing forward/backward
passes); the sandbox only *executes the action and returns a reward*, which is CPU /
memory / I/O work. Hence: microVM with snapshots, CPU/mem/storage, no GPU passthrough
needed in the sandbox.

## Key points
- The isolation spectrum, thin→thick, is: containers (shared host kernel) → gVisor
  (software "fake kernel") → microVMs/Firecracker (real kernel, minimal virtual HW) →
  full VMs (real kernel, full virtual HW). Thicker = stronger isolation + more
  hardware access, but slower and heavier.
- KVM is a Linux-kernel feature that uses CPU virtualization extensions (Intel VT-x /
  AMD-V) to run guests fast; it exists only on Linux, which is why Firecracker can't
  run natively on macOS/Windows.
- gVisor's "Sentry" is an application kernel written in Go that intercepts the
  sandboxed program's syscalls in user space, so the guest rarely touches the real
  host kernel.
- gVisor's default platform "systrap" traps syscalls in user space and needs no KVM,
  so gVisor runs even inside other VMs and on hosts lacking hardware virtualization.
- Firecracker boots a microVM in ~125–300ms and supports snapshot/restore that clones
  a running VM in ~tens of ms — faster than a cold boot — ideal for resetting to a
  known state repeatedly.
- A microVM's wall is hardware-enforced via KVM (escape requires a virtio/hypervisor
  bug — a narrow surface), whereas gVisor's wall is software-enforced (the Go Sentry
  is itself attack surface). The microVM boundary is generally considered stronger.
- Firecracker cannot do GPU passthrough, secure boot, or nested virtualization,
  because it strips firmware and PCI down to minimal virtio devices.
- Secure Boot requires UEFI firmware (OVMF/edk2) to cryptographically verify the boot
  chain; microVMs skip firmware (direct kernel boot) so they can't do it.
- GPU passthrough uses VFIO (hand a PCI device to a VM) plus an IOMMU (hardware that
  confines the device's memory access). Firecracker: no; gVisor: NVIDIA-only via
  nvproxy; Cloud Hypervisor and full VMs: yes.
- Nested virtualization (a VM running VMs inside it) works in full VMs but not
  reliably in microVMs or gVisor — which is why running Firecracker inside a
  Mac/Windows Linux VM is fragile (it needs nested KVM).
- All real OS-level isolation is Linux-only; cross-platform tools run a hidden
  lightweight Linux VM on Mac (Virtualization.framework) / Windows (WSL2/Hyper-V) and
  sandbox inside it. "Runs on all machines" means client-everywhere, execution-on-Linux.
- Kata Containers gives VM-strength isolation while still consuming standard OCI
  images, by running each container inside a lightweight VM (Firecracker/Cloud
  Hypervisor/QEMU backend).
- For RL sandboxes, a hardware-enforced boundary protects the integrity of the reward
  signal (a policy can learn to escape a weak sandbox and hack its reward); the GPU
  stays with the trainer, so the sandbox itself only needs CPU/memory/storage.

## References
- gVisor documentation — architecture (Sentry), platforms (systrap/KVM), GPU support
  (nvproxy): https://gvisor.dev/docs/ (accessed 2026-05-23)
- Firecracker project site and design (microVM, ~125ms boot, snapshotting, jailer):
  https://firecracker-microvm.github.io/ (accessed 2026-05-23)
- "Firecracker: Lightweight Virtualization for Serverless Applications", Agache et
  al., USENIX NSDI 2020 (boot time and codebase-size figures).
- Cloud Hypervisor project (VFIO/PCIe device passthrough):
  https://www.cloudhypervisor.org/ (accessed 2026-05-23)
- Kata Containers project (OCI containers backed by lightweight VMs):
  https://katacontainers.io/ (accessed 2026-05-23)
- StereOS (full-VM-per-agent positioning, source of the secure-boot/FIPS/GPU/nesting
  framing): https://stereos.ai/ (accessed 2026-05-23)

## Related
- (none yet)
