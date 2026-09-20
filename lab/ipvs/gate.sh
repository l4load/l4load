#!/usr/bin/env bash
set -euo pipefail
state=$(ipvsadm -Sn)
for proto in t u; do
    for backend in 10.0.2.2 10.0.3.2; do
        if grep -Fq -- "-a -$proto 198.18.0.1:8080 -r $backend:8080 " <<< "$state"; then
            ipvsadm -e "-$proto" 198.18.0.1:8080 -r "$backend:8080" -i -w 0
        fi
    done
done
