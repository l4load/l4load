import subprocess

state = subprocess.check_output(['/usr/sbin/ipvsadm', '-Sn'], text=True)
for line in state.splitlines():
    args = line.split()
    if args and args[0] == '-a':
        args[0] = '-e'
        args[args.index('-w') + 1] = '0'
        subprocess.run(['/usr/sbin/ipvsadm', *args], check=True)
