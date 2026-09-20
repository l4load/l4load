#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$(pwd)/lab/results/boot
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
image_url=https://cloud-images.ubuntu.com/noble/20260911/noble-server-cloudimg-amd64.img
curl --max-time 300 -fL "$image_url" -o "$out/base.img"
echo "612b2c0cc1bc413a6cb8c38fd611794caf0f2b436c50013d8b3794db12ad7354  $out/base.img" | sha256sum -c -
qemu-img create -f qcow2 -F qcow2 -b "$out/base.img" "$out/disk.img" 8G
ssh-keygen -q -t ed25519 -N '' -f "$out/key"
cat > "$out/user-data" <<USER
#cloud-config
users:
  - name: lab
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$out/key.pub")
USER
echo 'instance-id: l4load-boot' > "$out/meta-data"
cloud-localds "$out/seed.img" "$out/user-data" "$out/meta-data"
accel=tcg
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then accel=kvm; fi
echo "$accel" > "$out/accel.txt"
qemu-system-x86_64 -accel "$accel" -m 2048 -smp 2 -display none -serial "file:$out/serial.log" -drive "file=$out/disk.img,if=virtio" -drive "file=$out/seed.img,format=raw,if=virtio" -netdev user,id=n,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n &
vm=$!
trap 'kill "$vm" 2>/dev/null || true' EXIT
ssh_args=(-i "$out/key" -p 2222 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$out/known_hosts" -o BatchMode=yes -o ConnectTimeout=3)
remote() { ssh "${ssh_args[@]}" lab@127.0.0.1 "$@"; }
for attempt in $(seq 1 180); do
    if remote true 2>/dev/null; then break; fi
    kill -0 "$vm"
    sleep 2
done
remote sudo cloud-init status --wait
git archive HEAD | remote 'sudo mkdir -p /opt/l4load && sudo tar -x -C /opt/l4load'
remote sudo bash /opt/l4load/lab/boot/install.sh
for cycle in 1 2; do
    before=$(remote cat /proc/sys/kernel/random/boot_id)
    remote sudo systemctl reboot || true
    changed=false
    for attempt in $(seq 1 180); do
        after=$(remote cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)
        if [ -n "$after" ] && [ "$after" != "$before" ]; then changed=true; break; fi
        kill -0 "$vm"
        sleep 2
    done
    test "$changed" = true
    remote sudo systemctl is-system-running --wait || true
    remote sudo bash /opt/l4load/lab/boot/check.sh | tee "$out/boot-$cycle.txt"
    remote sudo journalctl -b -u l4load-ipvs -u l4load-lab-network --no-pager > "$out/journal-$cycle.txt"
done
echo HOST_REBOOT_PASS
