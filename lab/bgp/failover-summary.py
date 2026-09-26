import csv
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
fault_before = float((out / 'traffic-fault-start.txt').read_text())
fault_after = float((out / 'traffic-fault-applied.txt').read_text())
route_at = float((out / 'route-health-withdrawn-at.txt').read_text())
events = []
for line in (out / 'health1.jsonl').read_text().splitlines():
    if line.startswith('{'):
        events.append(json.loads(line))
withdraw = next(event['at'] for event in events if event['action'] == 'disable' and event['at'] >= fault_before)
result = {
    'fault_command_bracket_seconds': fault_after - fault_before,
    'withdraw_after_fault_applied_seconds': withdraw - fault_after,
    'route_observed_after_fault_applied_seconds': route_at - fault_after,
}
for protocol in ('tcp', 'udp'):
    with (out / f'useful-{protocol}.csv').open() as file:
        rows = list(csv.DictReader(file))
    errors = [i for i, row in enumerate(rows) if row['status'] != 'pass' and float(row['started_monotonic']) >= fault_before]
    assert errors and errors[0] > 0 and errors[-1] + 1 < len(rows)
    before, after = rows[errors[0] - 1], rows[errors[-1] + 1]
    assert before['status'] == after['status'] == 'pass'
    result[protocol] = {
        'errors': len(errors),
        'last_success_to_next_success_seconds': float(after['started_monotonic']) - float(before['started_monotonic']),
        'first_error_after_fault_applied_seconds': float(rows[errors[0]]['started_monotonic']) - fault_after,
        'first_success_after_route_observed_seconds': float(after['started_monotonic']) - route_at,
    }
print(json.dumps(result, indent=2))
