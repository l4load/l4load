# Host boot trial

On a disposable Ubuntu runner with QEMU and cloud-image-utils, run
`bash lab/boot/run.sh` from a committed checkout. It boots the pinned Ubuntu
24.04 image, installs the profile, then verifies two distinct rebooted kernels
and fresh source-preserving TCP/UDP traffic after each boot.

The lab adds a namespace topology service and an explicit ordering dependency.
This tests that deployment, not arbitrary host networking, physical NICs, HA or
connection continuity through a director reboot.

[The first trial passed](https://github.com/l4load/l4load/actions/runs/36166755057):
two distinct boot IDs, 64 new TCP/UDP flows after each boot, source IP preserved,
all four IPVS destinations healthy and no service restarts. It used kernel
6.8.0-139-generic and Keepalived 2.2.8. The stricter readiness timeout and added
diagnostic capture require a fresh run before merging.
