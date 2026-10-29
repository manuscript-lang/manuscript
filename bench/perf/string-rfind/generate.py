#!/usr/bin/env python3
"""Generate the fixed public last_index_of benchmark; never build or run it."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LENGTHS = [0, 1, 2, 7, 15, 16, 31, 32, 63, 64, 65, 128, 4096, 1048576]


def quoted(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\0', '\\u{0}').replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r') + '"'


def repeated(value, count):
    return f'{quoted(value)}.repeat({count}).get()'


def iterations(size):
    if size <= 128:
        return 1000000
    if size >= 262144:
        return 256
    if size >= 16384:
        return 4096
    if size >= 4096:
        return 65536
    return 100000


cases = []


def add(name, text, expression, needle, expected):
    # Construction formulas supply expected indexes; Python's independent Unicode
    # implementation checks them. No timed Manuscript operation supplies an oracle.
    assert text.rfind(needle) == expected, (name, expected, text.rfind(needle))
    size = len(text.encode('utf-8'))
    count = iterations(size)
    assert expected >= -1
    cases.append({
        'case': name,
        'hay_expression': expression,
        'hay_utf8_bytes': size,
        'hay_scalar_count': len(text),
        'needle': needle,
        'needle_utf8_bytes': len(needle.encode('utf-8')),
        'expected_scalar_index': expected,
        'iterations': count,
        'checksum': (expected + 19) * count,
    })


for size in LENGTHS:
    text = 'x' * size
    expression = repeated('x', size)
    add(f'one_miss_n{size}', text, expression, '!', -1)
    add(f'empty_needle_n{size}', text, expression, '', size)
    if size:
        rest = repeated('x', size - 1)
        add(f'one_end_n{size}', 'x' * (size - 1) + '!', rest + ' + "!"', '!', size - 1)
    if size > 1:
        add(f'one_start_n{size}', '!' + 'x' * (size - 1), '"!" + ' + rest, '!', 0)
    if size > 2:
        middle = size // 2
        expression = repeated('x', middle) + ' + "!" + ' + repeated('x', size - middle - 1)
        add(f'one_middle_n{size}', 'x' * middle + '!' + 'x' * (size - middle - 1), expression, '!', middle)

for size in [7, 63, 64, 4096, 1048576]:
    text = '!x' * (size // 2) + ('!' if size % 2 else '')
    expression = repeated('!x', size // 2) + ' + ' + quoted('!' if size % 2 else '')
    add(f'one_many_n{size}', text, expression, '!', 2 * ((size - 1) // 2))

add('two_tiny_miss', 'a', '"a"', 'ab', -1)
add('two_tiny_hit', 'ab', '"ab"', 'ab', 0)
add('two_tiny_valid_length_miss', 'ac', '"ac"', 'ab', -1)
add('two_short_end', 'x' * 61 + 'ab', repeated('x', 61) + ' + "ab"', 'ab', 61)
add('two_boundary_end', 'x' * 62 + 'ab', repeated('x', 62) + ' + "ab"', 'ab', 62)
add('two_boundary_miss', 'x' * 65, repeated('x', 65), 'ab', -1)
add('two_repeated_last', 'abababab', '"abababab"', 'ab', 6)
add('multi_empty_hay', '', '""', 'abcd', -1)
add('multi_tiny_longer', 'abc', '"abc"', 'abcd', -1)
add('multi_short_middle', 'x' * 14 + 'abcd' + 'x' * 13, repeated('x', 14) + ' + "abcd" + ' + repeated('x', 13), 'abcd', 14)
add('multi_boundary_end', 'x' * 60 + 'abcd', repeated('x', 60) + ' + "abcd"', 'abcd', 60)
add('multi_near_match_miss', 'a' * 63, repeated('a', 63), 'aaab', -1)
add('multi_overlap', 'abababa', '"abababa"', 'aba', 4)
add('multi_large_end', 'x' * 4092 + 'abcd', repeated('x', 4092) + ' + "abcd"', 'abcd', 4092)
add('multi_repetitive_miss', 'a' * 4096, repeated('a', 4096), 'a' * 255 + 'b', -1)
add('multi_repetitive_end', 'a' * 4095 + 'b', repeated('a', 4095) + ' + "b"', 'a' * 255 + 'b', 3840)
add('multi_repetitive_overlap', 'ab' * 2048, repeated('ab', 2048), 'ab' * 128, 3840)

add('unicode_two_end', 'é' * 31 + '!', repeated('é', 31) + ' + "!"', '!', 31)
add('unicode_two_start', '!' + 'é' * 31, '"!" + ' + repeated('é', 31), '!', 0)
add('unicode_two_middle', 'é' * 15 + '!' + 'é' * 16, repeated('é', 15) + ' + "!" + ' + repeated('é', 16), '!', 15)
add('unicode_two_miss', 'é' * 31 + 'x', repeated('é', 31) + ' + "x"', '!', -1)
add('unicode_multibyte_needle', 'aé日😀é', quoted('aé日😀é'), 'é', 4)
add('unicode_multiscalar_needle', 'é日xé日', quoted('é日xé日'), 'é日', 3)
add('unicode_empty_needle', 'é日😀', quoted('é日😀'), '', 3)
add('unicode_wide_end', '日😀' * 8 + '!', repeated('日😀', 8) + ' + "!"', '!', 16)
add('unicode_combining_needle', 'e\u0301e\u0301', quoted('e\u0301e\u0301'), '\u0301', 3)
add('unicode_large_scalar_index', 'é日😀' * 4096 + '!', repeated('é日😀', 4096) + ' + "!"', '!', 12288)

add('nul_one', '\0', quoted('\0'), '\0', 0)
add('nul_short_start', '\0' + 'x' * 62, quoted('\0') + ' + ' + repeated('x', 62), '\0', 0)
add('nul_short_end', 'x' * 62 + '\0', repeated('x', 62) + ' + ' + quoted('\0'), '\0', 62)
add('nul_repeated_last', 'a\0b\0', quoted('a\0b\0'), '\0', 3)
add('nul_hay_miss', 'a\0b', quoted('a\0b'), '!', -1)

assert len(cases) == 101, len(cases)
assert len({case['case'] for case in cases}) == len(cases)
identities = {case['case']: [case['hay_utf8_bytes'], case['iterations'], case['checksum']] for case in cases}
(ROOT / 'identities.json').write_text(json.dumps(identities, indent=2, ensure_ascii=False) + '\n')
(ROOT / 'oracle.json').write_text(json.dumps(cases, indent=2, ensure_ascii=False) + '\n')
source = '''import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn iterations_for(size: Int) Int:
    if size <= 128: return 1000000
    if size >= 262144: return 256
    if size >= 16384: return 4096
    if size >= 4096: return 65536

    return 100000

fn search_sum(text: String, needle: String, expected: Int) Int:
    let actual = text.last_index_of(needle).get(-1)
    if actual != expected: return -1

    return actual + 19

fn measure(name: String, text: String, needle: String, expected: Int) Int:
    let expected_sum = expected + 19
    if search_sum(text, needle, expected) != expected_sum: return 1

    let iterations = iterations_for(text.byte_length())
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += search_sum(text, needle, expected)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\\n")

'''
for case in cases:
    source += f'    if measure(\n        {quoted(case["case"])}, {case["hay_expression"]},\n        {quoted(case["needle"])}, {case["expected_scalar_index"]}\n    ) != 0: return 1\n\n'
source += '    return 0\n'
(ROOT / 'main.ms').write_text(source)
print(f'Prepared {len(cases)} fixed cases; Python scalar-index oracle verified; no builds or timing.')
