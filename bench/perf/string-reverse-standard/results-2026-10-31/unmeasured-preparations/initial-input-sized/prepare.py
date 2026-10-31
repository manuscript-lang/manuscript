"""Prepare exact-semantic sources and independent identities; never time workloads."""
from pathlib import Path
import hashlib
import itertools
import json
import subprocess

ROOT = Path('/workspace/text-discovery')
ROOT.mkdir(exist_ok=True)


def literal(text):
    # Both source languages accept scalar escapes with braces.
    import re
    return re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: '\\u{' + m[1] + '}',
                  json.dumps(text, ensure_ascii=False))


class Text:
    def __init__(self, *parts):
        self.parts = [(p, n) if isinstance(p, str) else p for p, n in parts]

    @property
    def value(self):
        return ''.join(p * n for p, n in self.parts)

    @property
    def ms(self):
        return ' + '.join(literal(p) if n == 1 else f'{literal(p)}.repeat({n}).get()'
                          for p, n in self.parts)

    @property
    def rust(self):
        return '[' + ', '.join(f'{literal(p)}.to_owned()' if n == 1 else
                                f'{literal(p)}.repeat({n})' for p, n in self.parts) + '].concat()'


def t(text):
    return Text((text, 1))


def repeated(text, count):
    return Text((text, count))


def iterations(size):
    if size <= 64:
        return 100_000
    if size <= 4096:
        return 4096
    if size <= 65536:
        return 128
    return 16


splits = [
    ('empty_text', t(''), t('::'), -1),
    ('empty_scalar_separator', t(''), t(''), -1),
    ('tiny_no_match', t('abc'), t('::'), -1),
    ('tiny_edges', t('::a::::b::'), t('::'), -1),
    ('tiny_overlap', t('aaaaa'), t('aa'), -1),
    ('nul_delimiter', t('a\0bé日\0b'), t('\0b'), -1),
    ('unicode_scalar_separator', t('é日😀e\u0301'), t(''), -1),
    ('cap_zero', t('a::b::c'), t('::'), 0),
    ('cap_one', t('a::b::c'), t('::'), 1),
    ('cap_two_truncates', t('a::b::c'), t('::'), 2),
    ('cap_scalar_two', t('é日😀e\u0301'), t(''), 2),
    ('common_fields', repeated('abcdefghijklmnopqrstuvwx||', 64), t('||'), -1),
    ('large_fields', repeated('abcdefghijklmnopqrstuvwx||', 4096), t('||'), -1),
    ('unicode_fields', repeated('é日😀§§', 1024), t('§§'), -1),
    ('repetitive_near_miss', repeated('a', 65536), Text(('a', 127), ('b', 1), ('a', 128)), -1),
    ('dense_periodic', repeated('aaaaaab', 1024), t('aaaaab'), -1),
    ('large_no_match', repeated('x', 1048576), t('needle'), -1),
    ('large_fields_cap_two', repeated('abcdefghijklmnopqrstuvwx||', 4096), t('||'), 2),
]
searches = [
    ('empty_empty', t(''), t('')),
    ('empty_nonempty', t(''), t('x')),
    ('tiny_first_last', t('abcabc'), t('ab')),
    ('tiny_absent', t('abc'), t('xy')),
    ('unicode_scalar_index', t('é日😀_é日😀'), t('日😀')),
    ('unicode_empty_needle', t('é日😀'), t('')),
    ('overlap', t('aaaaa'), t('aa')),
    ('nul_unicode', t('a\0bé日\0b'), t('\0b')),
    ('common_prose', repeated('the quick brown fox jumps over the lazy dog. ', 128), t('brown')),
    ('large_ascii_late', Text(('x', 65536), ('needle', 1)), t('needle')),
    ('large_unicode_late', Text(('é日😀', 16384), ('needle', 1)), t('needle')),
    ('repetitive_near_miss', repeated('a', 65536), Text(('a', 127), ('b', 1), ('a', 128))),
]
for size in [31, 32, 33]:
    searches.append((f'boundary_{size}', Text(('a', size - 2), ('::', 1)), t('::')))

ms_helpers = '''import stdout from "@std/io.ms"
import clock from "@std/time.ms"

type Run:
    text: String
    copies: Int

fn expected_parts(runs: List[Run]) List[String]:
    var output: List[String] = []
    for run in runs:
        for unused in 0..run.copies:
            output.append(run.text.clone())
    return output

fn split_result(text: String, separator: String, limit: Int) List[String]:
    if limit < 0: return text.split(separator)
    return text.split(separator, max_parts: limit)

fn parts_sum(parts: List[String]) Int:
    var checksum = 0
    for piece in parts:
        checksum += piece.byte_length() + 17
    return checksum

fn split_sum(text: String, separator: String, limit: Int, expected: List[String]) Int:
    let output = split_result(text, separator, limit)
    if output != expected: return -1
    return parts_sum(output)

fn search_sum(kind: Int, text: String, needle: String, expected: Int) Int:
    var actual = -1
    if kind == 0:
        actual = 0
        if text.contains(needle): actual = 1
    if kind == 1: actual = text.index_of(needle).get(-1)
    if kind == 2: actual = text.last_index_of(needle).get(-1)
    if actual != expected: return -1
    return actual + 18

fn measure_split(name: String, text: String, separator: String, limit: Int, expected: List[String], iterations: Int) Int:
    let expected_sum = parts_sum(expected)
    if split_sum(text, separator, limit, expected) != expected_sum: return 1
    var checksum = 0
    let started = clock().now()
    for unused in 0..iterations:
        checksum += split_sum(text, separator, limit, expected)
    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1
    let _written = stdout().write("{name},{text.byte_length()},{iterations},{elapsed},{checksum}\\n")
    return 0

fn measure_search(name: String, kind: Int, text: String, needle: String, expected: Int, iterations: Int) Int:
    let expected_sum = expected + 18
    if search_sum(kind, text, needle, expected) != expected_sum: return 1
    var checksum = 0
    let started = clock().now()
    for unused in 0..iterations:
        checksum += search_sum(kind, text, needle, expected)
    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1
    let _written = stdout().write("{name},{text.byte_length()},{iterations},{elapsed},{checksum}\\n")
    return 0

'''
ms_calls, ms_verify_calls, rust_cases, inventory, semantics = [], [], [], {}, []


def record(name, text, needle, count, expected, per_sum, limit=None):
    assert name not in inventory
    inventory[name] = [len(text.value.encode()), count, per_sum * count]
    semantics.append(dict(case=name, input_sha256=hashlib.sha256(text.value.encode()).hexdigest(),
                          needle_sha256=hashlib.sha256(needle.value.encode()).hexdigest(),
                          max_parts=limit, expected=expected))


for name, text, separator, limit in splits:
    name = 'split_' + name
    # Python is an independent scalar/nonoverlap oracle. cap is truncation,
    # deliberately unlike Rust splitn or Python maxsplit remainder semantics.
    expected = text.value.split(separator.value) if separator.value else list(text.value)
    if limit >= 0:
        expected = expected[:limit]
    runs = [(value, len(list(group))) for value, group in itertools.groupby(expected)]
    ms_expected = 'expected_parts([' + ', '.join(f'Run({literal(value)}, {count})'
                                               for value, count in runs) + '])'
    rust_expected = 'expected(&[' + ', '.join(f'({literal(value)}, {count})'
                                            for value, count in runs) + '])'
    count = iterations(len(text.value.encode()))
    per_sum = sum(len(part.encode()) + 17 for part in expected)
    args = f'{literal(name)}, {text.ms}, {separator.ms}, {limit}, {ms_expected}, {count}'
    ms_calls.append(f'    if measure_split({args}) != 0: return 1')
    ms_verify_calls.append(f'    if split_sum({text.ms}, {separator.ms}, {limit}, {ms_expected}) != {per_sum}: return 1')
    rust_cases.append(f'Case {{ name: {literal(name)}, kind: 3, text: {text.rust}, needle: {separator.rust}, limit: {limit}, index: 0, parts: {rust_expected}, iterations: {count}, per_sum: {per_sum} }}')
    record(name, text, separator, count, expected, per_sum, limit)

for name, text, needle in searches:
    for kind, operation in enumerate(['contains', 'index', 'last_index']):
        case_name = f'{operation}_{name}'
        if kind == 0:
            expected = int(needle.value in text.value)
        elif kind == 1:
            expected = text.value.find(needle.value)
        else:
            expected = text.value.rfind(needle.value)
        count = iterations(len(text.value.encode()))
        per_sum = expected + 18
        args = f'{literal(case_name)}, {kind}, {text.ms}, {needle.ms}, {expected}, {count}'
        ms_calls.append(f'    if measure_search({args}) != 0: return 1')
        ms_verify_calls.append(f'    if search_sum({kind}, {text.ms}, {needle.ms}, {expected}) != {per_sum}: return 1')
        rust_cases.append(f'Case {{ name: {literal(case_name)}, kind: {kind}, text: {text.rust}, needle: {needle.rust}, limit: -1, index: {expected}, parts: vec![], iterations: {count}, per_sum: {per_sum} }}')
        record(case_name, text, needle, count, expected, per_sum)

assert len(inventory) == 63
ms_main = 'export fn main() Int:\n    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\\n")\n'
(ROOT / 'text-discovery.ms').write_text(ms_helpers + ms_main + '\n'.join(ms_calls) + '\n    return 0\n')
(ROOT / 'text-discovery-verify.ms').write_text(ms_helpers + 'export fn main() Int:\n' + '\n'.join(ms_verify_calls) + '\n    return 0\n')

rust_source = r'''use std::{hint::black_box, time::Instant};
struct Case {
    name: &'static str, kind: u8, text: String, needle: String,
    limit: i64, index: i64, parts: Vec<String>, iterations: i64, per_sum: i64,
}
fn expected(runs: &[(&str, usize)]) -> Vec<String> {
    let mut result = Vec::new();
    for &(text, count) in runs {
        for _ in 0..count { result.push(text.to_owned()); }
    }
    result
}
#[inline(never)]
fn operation(case: &Case) -> i64 {
    if case.kind == 3 {
        let limit = if case.limit < 0 { usize::MAX } else { case.limit as usize };
        let actual: Vec<String> = if case.needle.is_empty() {
            case.text.chars().take(limit).map(|scalar| scalar.to_string()).collect()
        } else {
            case.text.split(case.needle.as_str()).take(limit).map(str::to_owned).collect()
        };
        if black_box(actual.as_slice()) != case.parts.as_slice() { return -1; }
        return actual.iter().map(|piece| piece.len() as i64 + 17).sum();
    }
    let actual = if case.kind == 0 {
        case.text.contains(case.needle.as_str()) as i64
    } else {
        let byte = if case.kind == 1 {
            case.text.find(case.needle.as_str())
        } else {
            case.text.rfind(case.needle.as_str())
        };
        byte.map(|at| case.text[..at].chars().count() as i64).unwrap_or(-1)
    };
    if actual != case.index { return -1; }
    actual + 18
}
fn main() {
    let corpus = vec![
__CASES__
    ]; // All setup precedes clocks.
    assert_eq!(corpus.len(), 63);
    let mode = std::env::args().nth(1);
    assert!(std::env::args().len() <= 2);
    if mode.as_deref() == Some("--verify") {
        for case in &corpus { assert_eq!(operation(black_box(case)), case.per_sum, "{}", case.name); }
        println!("verified {} exact scalar-search/owned-split outputs", corpus.len());
        return;
    }
    if mode.as_deref() == Some("--inventory") {
        println!("case,input_bytes,iterations,checksum");
        for case in &corpus {
            println!("{},{},{},{}", case.name, case.text.len(), case.iterations, case.per_sum * case.iterations);
        }
        return;
    }
    assert!(mode.is_none(), "unknown mode");
    println!("case,input_bytes,iterations,elapsed_ns,checksum");
    for case in &corpus {
        assert_eq!(operation(black_box(case)), case.per_sum, "{}", case.name);
        let mut checksum = 0_i64;
        let now = Instant::now();
        for _ in 0..case.iterations { checksum += black_box(operation(black_box(case))); }
        let elapsed = now.elapsed().as_nanos();
        assert_eq!(checksum, case.per_sum * case.iterations, "{}", case.name);
        println!("{},{},{},{},{}", case.name, case.text.len(), case.iterations, elapsed, checksum);
    }
}
'''
(ROOT / 'text-discovery.rs').write_text(rust_source.replace('__CASES__', ',\n'.join(rust_cases)))
(ROOT / 'identities.json').write_text(json.dumps(inventory, indent=2) + '\n')
(ROOT / 'semantics.json').write_text(json.dumps(semantics, ensure_ascii=False, indent=2) + '\n')
print(f'prepared {len(splits)} split + {len(searches)}*3 search = {len(inventory)} cases; no benchmarks executed')
