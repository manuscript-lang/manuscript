#!/usr/bin/env python3
"""Prepare independent Unicode-scalar padding oracles and fixed benchmark sources."""
import hashlib
import itertools
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def literal(text):
    escapes = {'"': '\\"', '\\': '\\\\', '\n': '\\n', '\r': '\\r', '\t': '\\t'}
    return '"' + ''.join(escapes.get(c, f'\\u{{{ord(c):x}}}' if ord(c) < 32 else c)
                         for c in text) + '"'


def expression(text):
    if len(text) <= 96:
        return literal(text)
    for width in range(1, 17):
        block = text[:width]
        count, remainder = divmod(len(text), width)
        tail = text[:remainder]
        if block * count + tail == text:
            result = f'{literal(block)}.repeat({count}).get()'
            return f'({result} + {literal(tail)})' if tail else result
    raise ValueError('use a short literal or a periodic oracle segment')


def oracle(text, target, padding, at_start):
    # Enumerate Unicode code points cyclically, independently of the runtime's
    # quotient/remainder byte-fill algorithm. Inputs contain no surrogates.
    needed = max(0, target - len(text))
    added = ''.join(itertools.islice(itertools.cycle(padding), needed)) if padding else ''
    return added + text if at_start else text + added


def expected_expression(text, result, at_start):
    if result == text:
        return expression(text)
    added = result[:-len(text)] if at_start and text else result[len(text):] if not at_start else result
    if not text:
        return expression(added)
    pieces = [expression(added), expression(text)] if at_start else [expression(text), expression(added)]
    return '(' + ' + '.join(pieces) + ')'


def iterations_for(*sizes):
    largest = max(sizes)
    if largest >= 262144:
        return 128
    if largest >= 4096:
        return 4096
    if largest >= 128:
        return 10000
    return 100000


identities = {}
inventory = []
calls = []


def add(name, text, target, padding, at_start):
    name = ('start_' if at_start else 'end_') + name
    result = oracle(text, target, padding, at_start)
    input_bytes, output_bytes = len(text.encode()), len(result.encode())
    iterations = iterations_for(input_bytes, output_bytes)
    identities[name] = [input_bytes, iterations, (output_bytes + 17) * iterations]
    inventory.append({'case': name, 'target_scalars': target, 'padding': padding,
                      'input_scalars': len(text), 'output_bytes': output_bytes,
                      'expected_sha256': hashlib.sha256(result.encode()).hexdigest()})
    calls.append(f'    if measure({literal(name)}, {expression(text)}, {target}, {literal(padding)}, '
                 f'{expected_expression(text, result, at_start)}, {str(at_start).lower()}, {iterations}) != 0: return 1')


for at_start in [True, False]:
    for label, padding in [('byte', '0'), ('ascii', 'ab'), ('unicode', 'é🙂')]:
        for target in [1, 2, 15, 16, 17, 32, 4096, 1048576]:
            add(f'{label}_target{target}', '!', target, padding, at_start)
    for label, text in [('empty', ''), ('tiny', 'é日😀'), ('long_ascii', 'q' * 1048576),
                        ('long_unicode', 'é日😀' * 116508)]:
        for kind, target, padding in [('negative', -1, 'ab'), ('empty_padding', len(text) + 8192, '')]:
            add(f'noop_{label}_{kind}', text, target, padding, at_start)
    add('positive_shorter', 'é日😀', 2, 'ab', at_start)
    for label, target, padding in [('byte', 1, '0'), ('unicode_small', 1, 'é🙂'),
                                    ('unicode_heap', 17, 'é🙂')]:
        add(f'empty_text_{label}', '', target, padding, at_start)
    for target in [4, 5, 17]:
        add(f'mixed_text_unicode_target{target}', 'é日😀', target, 'é🙂', at_start)
    add('mixed_text_ascii_target4', 'é日😀', 4, 'ab', at_start)
    for label, text in [('ascii', 'q' * 1048576), ('unicode', 'é日😀' * 116508)]:
        add(f'large_input_{label}_add3', text, len(text) + 3, 'é🙂', at_start)
    for target in [1, 2, 16, 17]:
        add(f'nul_target{target}', '', target, 'x\0y', at_start)
    for label, padding in [('byte', '0'), ('unicode', 'é🙂')]:
        for order, targets in [('grow_shrink', [32, 4096, 64, 1048576]),
                               ('shrink_grow', [1048576, 64, 4096, 32])]:
            if label == 'unicode' and order == 'shrink_grow':
                continue
            name = ('start_' if at_start else 'end_') + f'changing_{label}_{order}'
            outputs = [oracle('!', target, padding, at_start) for target in targets]
            iterations = 128  # Four pad operations per loop; identity counts operations.
            identities[name] = [1, iterations, sum(len(s.encode()) + 17 for s in outputs) * (iterations // 4)]
            inventory.append({'case': name, 'targets_scalars': targets, 'padding': padding,
                              'input_scalars': 1, 'output_bytes': [len(s.encode()) for s in outputs],
                              'expected_sha256': [hashlib.sha256(s.encode()).hexdigest() for s in outputs]})
            expected = ', '.join(expected_expression('!', s, at_start) for s in outputs)
            calls.append(f'    if measure_changing({literal(name)}, "!", {literal(padding)}, '
                         f'{targets}, [{expected}], {str(at_start).lower()}, {iterations}) != 0: return 1')

header = '''import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn consume(result: String, expected: String) Int:
    if result != expected: return -1
    return result.byte_length() + 17

fn pad_sum(text: String, target: Int, padding: String, expected: String, at_start: Bool) Int:
    if at_start: return consume(text.pad_start(target, padding), expected)
    return consume(text.pad_end(target, padding), expected)

fn measure(name: String, text: String, target: Int, padding: String, expected: String, at_start: Bool, iterations: Int) Int:
    let expected_sum = expected.byte_length() + 17
    if pad_sum(text, target, padding, expected, at_start) != expected_sum: return 1
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += pad_sum(text, target, padding, expected, at_start)
    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1
    let _written = stdout().write("{name},{text.byte_length()},{iterations},{elapsed},{checksum}\\n")
    return 0

fn measure_changing(name: String, text: String, padding: String, targets: List[Int], expected: List[String], at_start: Bool, iterations: Int) Int:
    if iterations % 4 != 0: return 1
    let t0 = targets.get(0)
    let t1 = targets.get(1)
    let t2 = targets.get(2)
    let t3 = targets.get(3)
    let e0 = expected.get(0)
    let e1 = expected.get(1)
    let e2 = expected.get(2)
    let e3 = expected.get(3)
    let expected_cycle = e0.byte_length() + e1.byte_length() + e2.byte_length() + e3.byte_length() + 68
    let warm = pad_sum(text, t0, padding, e0, at_start) + pad_sum(text, t1, padding, e1, at_start) + pad_sum(text, t2, padding, e2, at_start) + pad_sum(text, t3, padding, e3, at_start)
    if warm != expected_cycle: return 1
    var checksum = 0
    let started = clock().now()
    for cycle in 0..(iterations / 4):
        checksum += pad_sum(text, t0, padding, e0, at_start)
        checksum += pad_sum(text, t1, padding, e1, at_start)
        checksum += pad_sum(text, t2, padding, e2, at_start)
        checksum += pad_sum(text, t3, padding, e3, at_start)
    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_cycle * (iterations / 4): return 1
    let _written = stdout().write("{name},{text.byte_length()},{iterations},{elapsed},{checksum}\\n")
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\\n")
'''
(ROOT / 'main.ms').write_text(header + '\n'.join(calls) + '\n    return 0\n')
(ROOT / 'identities.json').write_text(json.dumps(identities, indent=2, ensure_ascii=False) + '\n')
(ROOT / 'oracle.json').write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + '\n')
print(f'Prepared {len(identities)} independent identities')

# Functional fixtures use the same independent scalar oracle, not String.pad.
test_rows = []
for text, target, padding in [("!", t, p) for t in [1, 2, 15, 16, 17, 31, 32] for p in ["0", "ab", "é🙂"]]:
    for side in [True, False]:
        result = oracle(text, target, padding, side)
        method = "pad_start" if side else "pad_end"
        test_rows.append(f"    try expect_equal({literal(text)}.{method}({target}, {literal(padding)}), {literal(result)})")
for text, target, padding in [("", 1, "0"), ("", 2, "x\0y"), ("", 17, "x\0y"), ("é日😀", 4, "é🙂"), ("é日😀", 5, "ab"), ("é日😀", 17, "é🙂")]:
    for side in [True, False]:
        result = oracle(text, target, padding, side)
        method = "pad_start" if side else "pad_end"
        test_rows.append(f"    try expect_equal({literal(text)}.{method}({target}, {literal(padding)}), {literal(result)})")
fixture = 'import {expect_equal, expect_fault} from "@std/test.ms"\n\ntest "padding exact outputs cross cache and inline boundaries":\n' + '\n'.join(test_rows) + '\n'
fixture += '''
test "padding no-op cases preserve text":
    for target in [-9223372036854775808, -1, 0, 2, 3]:
        try expect_equal("é日😀".pad_start(target, "ab"), "é日😀")
        try expect_equal("é日😀".pad_end(target, "é🙂"), "é日😀")
    try expect_equal("é日😀".pad_start(9223372036854775807, ""), "é日😀")
    try expect_equal("".pad_end(9223372036854775807, ""), "")

test "large padding and small growth preserve exact bytes":
    let prefix = "q".repeat(1048575).get()
    try expect_equal("!".pad_start(1048576, "q"), prefix + "!")
    try expect_equal("!".pad_end(1048576, "q"), "!" + prefix)
    let mixed = "é日😀".repeat(116508).get()
    try expect_equal(mixed.pad_start(349527, "é🙂"), "é🙂é" + mixed)
    try expect_equal(mixed.pad_end(349527, "é🙂"), mixed + "é🙂é")

test "padding over the string limit faults before allocation":
    let start_message = try expect_fault(fn():
        let _ = "!".pad_start(9223372036854775807, "é🙂")
    )
    let end_message = try expect_fault(fn():
        let _ = "!".pad_end(9223372036854775807, "é🙂")
    )
    try expect_equal(start_message, "string: limit exceeded")
    try expect_equal(end_message, "string: limit exceeded")
'''
(ROOT / "exploratory/source-tests.ms").write_text(fixture)
