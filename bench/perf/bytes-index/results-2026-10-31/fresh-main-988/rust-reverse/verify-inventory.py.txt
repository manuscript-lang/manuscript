"""Untimed, independent source/corpus audit; does not execute the Rust binary."""
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT = Path('/workspace/reverse-discovery')
CANONICAL = Path('/workspace/manuscript/bench/perf/string-normalization-rollback/inputs')
rust = (ROOT / 'reverse-control.rs').read_text()
ms = (CANONICAL / 'reverse-full.ms').read_text()
literal = r'("(?:[^"\\]|\\.)*")'


def decode(value):
    value = re.sub(r'\\u\{([0-9a-fA-F]+)\}',
                   lambda match: json.dumps(chr(int(match[1], 16)))[1:-1], value)
    return json.loads(value)


def patterns(source, prefix):
    return [(name, decode(forward), decode(backward)) for name, forward, backward
            in re.findall(prefix + r'\(\s*"([^"]+)",\s*' + literal + r',\s*' + literal + r'\s*\)', source)]


rust_patterns = patterns(rust, '')
ms_patterns = patterns(ms, 'Pattern')
assert rust_patterns == ms_patterns and len(rust_patterns) == 9
rust_lengths = [ast.literal_eval('[' + value + ']')
                for value in re.findall(r'for length in \[([^]]+)\]', rust)]
ms_lengths = [ast.literal_eval('[' + value + ']')
              for value in re.findall(r'for length in \[([^]]+)\]', ms)]
assert rust_lengths == ms_lengths and len(rust_lengths) == 2
rust_copies = ast.literal_eval('[' + re.search(r'for copies in \[([^]]+)\]', rust)[1] + ']')
ms_copies = ast.literal_eval('[' + re.search(r'for copies in \[([^]]+)\]', ms)[1] + ']')
assert rust_copies == ms_copies


def iterations_for(size):
    if size <= 32:
        return 1_000_000
    if size >= 262_144:
        return 16
    if size >= 4_096:
        return 1_024
    return 100_000


rows = {}
contents = []


def add(name, text, expected):
    assert name not in rows
    assert text[::-1] == expected, name
    size = len(text.encode())
    expected_size = len(expected.encode())
    assert size == expected_size
    iterations = iterations_for(size)
    rows[name] = [size, iterations, (expected_size + 17) * iterations]
    contents.append(dict(case=name, input_sha256=hashlib.sha256(text.encode()).hexdigest(),
                         expected_sha256=hashlib.sha256(expected.encode()).hexdigest()))


for name, forward, backward in rust_patterns[:2]:
    assert forward.isascii() and len(forward) == len(backward) == 8
    for length in rust_lengths[0]:
        copies, tail = divmod(length, 8)
        add(f'{name}_n{length}', forward * copies + forward[:tail],
            backward[8 - tail:8] + backward * copies)
for name, forward, backward in rust_patterns[2:]:
    for copies in rust_copies:
        add(f'{name}_copies{copies}', forward * copies, backward * copies)
for length in rust_lengths[1]:
    ascii_text = 'x' * length
    add(f'late_unicode_{length}', ascii_text + 'é日😀', '😀日é' + ascii_text)
    add(f'early_unicode_{length}', 'é日😀' + ascii_text, ascii_text + '😀日é')

canonical_rows = json.loads((CANONICAL / 'reverse-full-identities.json').read_text())
assert len(rows) == len(canonical_rows) == 83
assert list(rows) == list(canonical_rows), 'case order differs'
assert rows == canonical_rows, 'case identity differs'
(ROOT / 'inventory.json').write_text(json.dumps(rows, indent=2) + '\n')
(ROOT / 'content-identities.json').write_text(json.dumps(contents, indent=2) + '\n')
summary = {
    'case_count': len(rows),
    'canonical_identities_matched': True,
    'source_pattern_literals_and_iteration_arrays_match': True,
    'all_explicit_expected_outputs_match_independent_scalar_reverse': True,
    'rust_binary_executed': False,
    'benchmark_timings_collected': False,
    'canonical_ms_sha256': hashlib.sha256((CANONICAL / 'reverse-full.ms').read_bytes()).hexdigest(),
    'canonical_identities_sha256': hashlib.sha256((CANONICAL / 'reverse-full-identities.json').read_bytes()).hexdigest(),
    'minimum_input_bytes': min(row[0] for row in rows.values()),
    'maximum_input_bytes': max(row[0] for row in rows.values()),
}
(ROOT / 'inventory-audit.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
