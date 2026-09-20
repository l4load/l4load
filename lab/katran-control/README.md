# Control-plane write rejection

Uses pinned upstream Katran in non-testing mode.
The only source-tree additions are a standalone probe and its CMake target.

The probe creates a two-backend ring, freezes its kernel map, changes a weight and
compares the API result, userspace model and full kernel ring. A reproduction
marker means the suspected false-success behaviour was observed, not that the
product passed acceptance. Map freezing is intentionally irreversible; use only
disposable Linux. No program is attached to a host interface.

This covers permanent write rejection. Packet behaviour, partial writes, temporary
failure recovery and any proposed fix require additional experiments. Do not infer
production incidence or novelty. See the pinned public Katran source/license; this
probe does not contain corporate source or data.

[Verified run](https://github.com/l4load/l4load/actions/runs/36131903013/job/108060858905),
2026-09-25: 60 tests in four upstream suites passed. The probe returned
`api_success=true`, `model_changed=true`, `kernel_ring_unchanged=true` after the
map was frozen. All ring entries were read back and compared to the pre-fault
snapshot. The API result alone therefore did not establish applied state in this
experiment. No packet traffic or transient recovery was tested.
