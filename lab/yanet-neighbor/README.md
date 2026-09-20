# Neighbor reload experiment

Pinned YANET's interface update clears its previous ID/name map before the
neighbor dump uses that map to preserve static entries. The candidate passes
an explicit previous-map snapshot during remapping and uses the current map
for ordinary refreshes.

CI runs the original neighbor tests, adds a regression that must fail upstream,
then applies the candidate and requires all neighbor tests to pass. The
regression covers unchanged interfaces, reassigned IDs, refresh and removal.
Results are pending. This does not yet prove the cause of the intermittent
packet-level reload failure or qualify concurrent updates and production use.
