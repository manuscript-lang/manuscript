"""Read-only, dependency-free verification of the rejected experiment evidence."""
import csv
import hashlib
import json
import math
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parent / 'results-2026-10-31'


def load(path):
    return json.loads((ROOT / path).read_text())


manifest = load('publication-manifest.json')
for name, entry in manifest['text_artifacts'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == entry['sha256'], name
    if entry.get('encoding') == 'lossless-utf8-json':
        original = load(name)['original_utf8'].encode()
        assert hashlib.sha256(original).hexdigest() == entry['original_sha256'], name
assert not manifest['helper_ir_published'] and not manifest['binary_files_published']
for path in ROOT.rglob('*'):
    if path.is_file():
        with path.open('rb') as source:
            assert not source.read(8).startswith((b'\x7fELF', b'!<arch>')), path
        assert path.suffix not in ('.a', '.o', '.ll', '.bc', '.pyc'), path

replay = load('replay-record.json')
assert replay['complete'] and all(replay['integrity_after'].values())
assert all(replay['programs_integrity_after'].values())
assert len(replay['integrity_after']) == 17 and len(replay['programs_integrity_after']) == 34
assert all(command['exit'] == 0 for command in replay['commands'])
total_rows = total_paired = 0
contrasts = [('baseline', 'reverse'), ('word', 'both'), ('baseline', 'both'),
             ('baseline', 'word'), ('reverse', 'both')]
for suite, count in [('reverse', 83), ('normalize', 100), ('byte', 220), ('lines', 16), ('text', 63)]:
    record = load(f'{suite}-matrix/record.json')
    assert record['complete'] and record['cases'] == count
    identities = load(f'{suite}-identities.json')
    assert len(identities) == count
    labels, rounds = list(record['programs']), len(record['orders'])
    assert rounds == len(labels) * 2
    assert all(sum(order.index(label) == position for order in record['orders']) == 2
               for label in labels for position in range(len(labels)))
    with (ROOT / f'{suite}-matrix/samples.csv').open(newline='') as source:
        rows = list(csv.DictReader(source))
    indexed = {(row['case'], row['variant'], int(row['pair'])): row for row in rows}
    assert len(indexed) == len(rows) == count * len(labels) * rounds
    for case, expected in identities.items():
        for label in labels:
            for pair in range(rounds):
                row = indexed[case, label, pair]
                assert [int(row[key]) for key in ('input_bytes', 'iterations', 'checksum')] == expected
                assert int(row['elapsed_ns']) > 0
    with (ROOT / f'{suite}-paired.csv').open(newline='') as source:
        paired = list(csv.DictReader(source))
    by_pair = {(row['case'], row['before'], row['after']): row for row in paired}
    comparisons = contrasts + ([(label, 'rust') for label in labels if label != 'rust'] if 'rust' in labels else [])
    assert len(by_pair) == len(paired) == count * len(comparisons)
    for before, after in comparisons:
        for case in identities:
            lhs = [int(indexed[case, before, pair]['elapsed_ns']) / int(indexed[case, before, pair]['iterations']) for pair in range(rounds)]
            rhs = [int(indexed[case, after, pair]['elapsed_ns']) / int(indexed[case, after, pair]['iterations']) for pair in range(rounds)]
            deltas = [y - x for x, y in zip(lhs, rhs)]
            expected = {'before_median_ns': median(lhs), 'after_median_ns': median(rhs),
                        'change_pct': 100 * (median(rhs) / median(lhs) - 1),
                        'paired_median_delta_ns': median(deltas), 'paired_min_delta_ns': min(deltas),
                        'paired_max_delta_ns': max(deltas), 'before_min_ns': min(lhs),
                        'before_max_ns': max(lhs), 'after_min_ns': min(rhs), 'after_max_ns': max(rhs)}
            row = by_pair[case, before, after]
            assert int(row['rounds']) == rounds
            assert int(row['slower_pairs']) == sum(delta > 0 for delta in deltas)
            assert all(math.isclose(float(row[key]), value, rel_tol=1e-12, abs_tol=1e-9)
                       for key, value in expected.items()), (suite, case, before, after)
    total_rows += len(rows)
    total_paired += len(paired)
assert total_rows == 22012 and total_paired == 3874

rss = load('rss-results/record.json')
assert rss['complete'] and len(rss['samples']) == 50
for item in rss['samples']:
    assert item['exit'] == 0 and item['stdout_matches'] and item['stderr_empty']
    prefix = f"{item['mode']}-{item['repetition']}-{item['label']}"
    assert load(f'rss-results/{prefix}.json') == item['metrics']
    assert item['metrics']['maxrss_kib'] > 0
    expected = b'4194304\n' if item['mode'] == 'ascii' else b'5242880\n'
    assert (ROOT / f'rss-results/{prefix}.stdout').read_bytes() == expected
    assert not (ROOT / f'rss-results/{prefix}.stderr').read_bytes()

baseline = (ROOT / 'states/baseline/string.rs.txt').read_bytes()
candidate = (ROOT / 'states/reverse/string.rs.txt').read_bytes()
branch = (b'        if let Ok(text) = core::str::from_utf8(text) {\n'
          b'            let reversed: String = text.chars().rev().collect();\n'
          b'            return from_buf(reversed.into_bytes());\n'
          b'        }\n')
assert candidate.count(branch) == 1 and candidate.replace(branch, b'', 1) == baseline
proof = load('production-restoration.json')
assert proof['crates_diff_empty_after_restore']
assert proof['baseline_sha256'] == hashlib.sha256(baseline).hexdigest()
assert proof['candidate_sha256'] == hashlib.sha256(candidate).hexdigest()
assert load('inputs/text/identities.json') == load('text-identities.json')
assert hashlib.sha256((ROOT / 'inputs/text/semantics.json').read_bytes()).hexdigest() == '9a62925675e245c87cbb23673640c7fd790262525c497091b38775c126117c9a'
print(f'verified {total_rows:,} raw rows, {total_paired:,} paired summaries, 50 RSS children, exact source restoration and published hashes; no native programs executed')
