#!/usr/bin/env bash
set -euo pipefail
for proto in t u; do
    for backend in 10.0.2.2 10.0.3.2; do
        ipvsadm -e "-$proto" 198.18.0.1:8080 -r "$backend:8080" -i -w 0
    done
done
