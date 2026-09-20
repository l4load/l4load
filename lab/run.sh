#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Requires Linux x86_64'; exit 1; }
for command in qemu-system-x86_64 busybox cpio go python3 curl timeout; do
    command -v "$command" >/dev/null || { echo "Missing $command"; exit 1; }
done
mkdir -p lab/results
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root"/{bin,dev,proc,sys,tmp}
cp "$(command -v busybox)" "$root/bin/busybox"
cp lab/init "$root/init"
chmod +x "$root/init"
sudo mknod "$root/dev/console" c 5 1
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go test -c -o "$root/test" ./internal/balance
python3 - <<'PY'
import hashlib, json, pathlib, subprocess
kernel = json.loads(pathlib.Path('lab/baselines.json').read_text())['kernel']
p = pathlib.Path('lab/results/vmlinuz')
if not p.exists():
    subprocess.run(['curl', '-fsSL', '--max-time', '90', kernel['url'], '-o', str(p)], check=True)
if hashlib.sha256(p.read_bytes()).hexdigest() != kernel['sha256']:
    raise SystemExit('Kernel checksum mismatch; review and repin the upstream artifact')
PY
(cd "$root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null) | gzip > lab/results/initramfs.gz
python3 - <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import hashlib, json, platform, subprocess
manifest = {
    'started_at': datetime.now(timezone.utc).isoformat(),
    'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'host': platform.platform(),
    'qemu': subprocess.check_output(['qemu-system-x86_64', '--version'], text=True).splitlines()[0],
    'go': subprocess.check_output(['go', 'version'], text=True).strip(),
    'evidence': 'emulated Linux loopback functionality; no comparative performance measurement',
    'machine': 'pc', 'cpu': 'qemu64', 'accelerator': 'tcg', 'vcpus': 2, 'memory_mib': 512,
    'network': 'guest loopback only; no external NIC',
    'sha256': {p: hashlib.sha256(Path('lab/results', p).read_bytes()).hexdigest() for p in ['vmlinuz', 'initramfs.gz']}
}
Path('lab/results/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
set +e
timeout 180 qemu-system-x86_64 -machine pc,accel=tcg -cpu qemu64 -smp 2 -m 512 \
    -kernel lab/results/vmlinuz -initrd lab/results/initramfs.gz \
    -append 'console=ttyS0 rdinit=/init panic=-1' -display none -serial stdio \
    -monitor none -nic none -no-reboot 2>&1 | tee lab/results/serial.log
status=${PIPESTATUS[0]}
set -e
python3 - "$status" <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import json, sys
p = Path('lab/results/manifest.json')
m = json.loads(p.read_text())
log = Path('lab/results/serial.log').read_text()
m['finished_at'] = datetime.now(timezone.utc).isoformat()
m['qemu_exit'] = int(sys.argv[1])
m['passed'] = m['qemu_exit'] == 0 and '\nL4LOAD_TEST_EXIT=0\n' in log
p.write_text(json.dumps(m, indent=2) + '\n')
if not m['passed']:
    raise SystemExit('Guest checks failed; inspect lab/results/serial.log')
PY
