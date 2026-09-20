# Host boot trial

On a disposable Ubuntu runner with QEMU and cloud-image-utils, run
`bash lab/boot/run.sh` from a committed checkout. It boots the pinned Ubuntu
24.04 image, installs the profile, then verifies two distinct rebooted kernels
and fresh source-preserving TCP/UDP traffic after each boot.

The lab adds a namespace topology service and an explicit ordering dependency.
This tests that deployment, not arbitrary host networking, physical NICs, HA or
connection continuity through a director reboot. Runtime qualification pending.
