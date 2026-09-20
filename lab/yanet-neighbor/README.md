# Neighbor reload experiment

Evaluate the existing [upstream PR #335](https://github.com/yanet-platform/yanet/pull/335)
by ezhk, pinned at `dacf4015f794e978c74200bb49f35472114d66aa`.
It preserves static neighbors during interface ID changes and gives deferred
updates ownership of their input data. This is upstream work, not a new L4Load fix.

CI runs the original neighbor tests, installs the PR's regression test alone
and requires it to fail, then installs its two implementation files and requires
all tests to pass. Explicit neighbor clear must still remove static entries.
[Run36144972495](https://github.com/l4load/l4load/actions/runs/36144972495) passed
the before/after checks. Packet-level reload and concurrent updates require separate
qualification. The earlier local candidate was discarded after finding this PR.
