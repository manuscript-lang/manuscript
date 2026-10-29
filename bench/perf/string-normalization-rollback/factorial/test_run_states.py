#!/usr/bin/env python3
"""Exercise only fake producers; never invokes Manuscript, cargo or a real bench."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

RUNNER = Path(__file__).with_name('run_states.py')
LABELS = ['baseline', 'normalize_only', 'reverse_only', 'combined']
HEADER = 'case,input_bytes,iterations,elapsed_ns,checksum\n'
ROOT = Path(tempfile.mkdtemp(prefix='factorial-fake-', dir=RUNNER.parent))
SOURCE = ROOT / 'fake-source.ms'
SOURCE.write_text('FAKE source-hash input only; not executable.\n')
IDENTITIES = ROOT / 'identities.json'
IDENTITIES.write_text(json.dumps({'a': [2, 3, 57], 'b': [0, 5, 85]}))
RESULTS = ROOT / 'results'


def fake(label, mode, directory):
    path = directory / label
    path.parent.mkdir(exist_ok=True)
    times = {'baseline': (9, 15), 'normalize_only': (12, 20),
             'reverse_only': (6, 10), 'combined': (15, 25)}[label]
    good = f'a,2,3,{times[0]},57\nb,0,5,{times[1]},85\n'
    output = HEADER + good
    code = 0
    if mode == 'missing':
        output = HEADER + good.splitlines(keepends=True)[0]
    elif mode == 'duplicate':
        output = HEADER + good.splitlines(keepends=True)[0] + good
    elif mode == 'unknown':
        output = (HEADER + good).replace('b,0,5,', 'unknown,0,5,')
    elif mode == 'checksum':
        output = (HEADER + good).replace(',57\n', ',58\n')
    elif mode == 'zeroelapsed':
        output = HEADER + 'a,2,3,0,57\n' + good.splitlines(keepends=True)[1]
    elif mode == 'nonzero':
        code = 7
    program = '#!/usr/bin/env python3\nimport sys\n'
    if mode == 'late_nonzero':
        counter = directory / f'{label}-count'
        program += f'from pathlib import Path\np=Path({str(counter)!r})\nn=int(p.read_text())+1 if p.exists() else 1\np.write_text(str(n))\n'
        program += f'print({output!r},end="")\nprint("fake stderr",file=sys.stderr)\nsys.exit(7 if n>1 else 0)\n'
    else:
        program += f'print({output!r},end="")\nprint("fake stderr",file=sys.stderr)\nsys.exit({code})\n'
    path.write_text(program)
    path.chmod(0o755)
    return str(path)


def invoke(mode, prefix, bad_state='baseline'):
    directory = ROOT / ('programs-' + prefix)
    programs = {label: fake(label, mode if label == bad_state else 'success', directory)
                for label in LABELS}
    config = ROOT / (prefix + '.json')
    config.write_text(json.dumps(programs))
    command = [sys.executable, str(RUNNER), '--programs', str(config),
               '--identity-file', str(IDENTITIES), '--source', str(SOURCE),
               '--output-dir', str(RESULTS), '--prefix', prefix]
    result = subprocess.run(command, text=True, capture_output=True)
    return result, RESULTS / prefix, command


def read_csv(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


result, directory, command = invoke('success', 'success')
assert result.returncode == 0, result.stderr
status = json.loads((directory / 'run-status.json').read_text())
assert status['validated_producers'] == 32 and status['validated_warmups'] == 4
assert status['raw_rows'] == 56 and len(read_csv(directory / 'raw-samples.csv')) == 56
assert len(read_csv(directory / 'state-summary.csv')) == 8
assert len(read_csv(directory / 'paired-samples.csv')) == 42
paired = read_csv(directory / 'paired-summary.csv')
assert len(paired) == 6
for row in paired:
    expected = {'normalize_only': 1.0, 'reverse_only': -1.0, 'combined': 2.0}[row['state']]
    assert float(row['paired_delta_median_ns']) == expected
    assert int(row['slower_rounds']) == (7 if expected > 0 else 0)
    assert int(row['faster_rounds']) == (7 if expected < 0 else 0)
invocations = [json.loads(line) for line in (directory / 'invocations.jsonl').read_text().splitlines()]
assert len(invocations) == 32 and all(row['validated'] for row in invocations)
protocol = json.loads((directory / 'protocol.json').read_text())
for round_record in protocol['round_schedule']:
    actual = [row['state'] for row in invocations if row['stage'] == 'round'
              and row['round'] == round_record['round']]
    assert actual == round_record['order']
for label in LABELS:
    counts = [sum(round_record['order'][slot] == label for round_record in protocol['round_schedule'])
              for slot in range(4)]
    assert sorted(counts) == [1, 2, 2, 2]
raw_digest = hashlib.sha256((directory / 'raw-samples.csv').read_bytes()).hexdigest()
repeat = subprocess.run(command, text=True, capture_output=True)
assert repeat.returncode != 0
assert hashlib.sha256((directory / 'raw-samples.csv').read_bytes()).hexdigest() == raw_digest

for mode in ['missing', 'duplicate', 'unknown', 'checksum', 'zeroelapsed', 'nonzero']:
    result, directory, _ = invoke(mode, mode)
    assert result.returncode != 0
    status = json.loads((directory / 'run-status.json').read_text())
    assert status['validated_producers'] == 0 and status['raw_rows'] == 0
    assert not status['summaries_emitted']
    assert len(read_csv(directory / 'raw-samples.csv')) == 0
    assert not any((directory / name).exists() for name in
                   ['state-summary.csv', 'paired-samples.csv', 'paired-summary.csv'])
    invocation = json.loads((directory / 'invocations.jsonl').read_text())
    assert invocation['validated'] is False
    assert invocation['producer_returncode'] == (7 if mode == 'nonzero' else 0)
    assert (directory / invocation['stdout']).read_text().startswith(HEADER)
    assert (directory / invocation['stderr']).read_text() == 'fake stderr\n'

result, directory, _ = invoke('late_nonzero', 'late_nonzero', 'normalize_only')
assert result.returncode != 0
status = json.loads((directory / 'run-status.json').read_text())
assert status['validated_warmups'] == 4 and status['validated_producers'] == 5
assert status['raw_rows'] == 2 and len(read_csv(directory / 'raw-samples.csv')) == 2
assert not status['summaries_emitted']
assert not any((directory / name).exists() for name in
               ['state-summary.csv', 'paired-samples.csv', 'paired-summary.csv'])
invocations = [json.loads(line) for line in (directory / 'invocations.jsonl').read_text().splitlines()]
assert len(invocations) == 6 and invocations[-1]['validated'] is False
assert invocations[-1]['producer_returncode'] == 7
print('PASS: fake success; seven-round schedule/signs; overwrite refusal; missing/duplicate/unknown/checksum/zeroelapsed/nonzero rejection; late-failure partial preservation.')
print('Fake fixture evidence:', ROOT)
