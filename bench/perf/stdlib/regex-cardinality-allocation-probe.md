# Reproduce the capture-shape allocation diagnostic

This external-only host Rust harness forwards the global allocator to `System`
and counts allocation requests and logical live sizes around one regex call,
complete output checks, and destruction. It does not instrument the Manuscript
runtime allocator or measure RSS. See [the result report](regex-cardinality-results-2026-10-29.md).

Save the Rust fence below as `/tmp/regex-cardinality-alloc/harness.rs`. Run this setup from
the candidate repository root; it copies just the regex sources into temporary
packages and uses unchanged runtime path dependencies. The baseline is
`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.

```python
from pathlib import Path
import json
import subprocess

root = Path.cwd().resolve()
probe = Path('/tmp/regex-cardinality-alloc')
probe.mkdir(exist_ok=True)
features = ["unicode-case", "unicode-gencat", "unicode-script", "unicode-perl",
            "unicode-bool", "unicode-age", "unicode-segment", "perf-inline",
            "perf-literal", "perf-onepass", "perf-backtrack", "perf-dfa"]
for name in ('baseline', 'candidate'):
    folder = probe / name
    (folder / 'src').mkdir(parents=True, exist_ok=True)
    for file in ('lib.rs', 'ffi.rs', 'translate.rs'):
        path = f'crates/ms-std-regex/src/{file}'
        data = (subprocess.check_output(['git', 'show',
                f'4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192:{path}'])
                if name == 'baseline' else (root / path).read_bytes())
        (folder / 'src' / file).write_bytes(data)
    manifest = '\n'.join([
        '[package]', f'name = "alloc-{name}"', 'version = "0.1.0"',
        'edition = "2024"', '[lib]', 'name = "regex_under_test"',
        'path = "src/lib.rs"', '[[bin]]', f'name = "alloc-{name}"',
        'path = "../harness.rs"', '[dependencies]',
        'regex = { version = "=1.13.1", default-features = false, features = '
            + json.dumps(features) + ' }',
        'ms-rt = { path = ' + json.dumps(str(root / 'crates/ms-rt')) + ' }',
        'ms-rt-abi = { path = ' + json.dumps(str(root / 'crates/ms-rt-abi')) + ' }',
    ])
    (folder / 'Cargo.toml').write_text(manifest + '\n')
(probe / 'Cargo.toml').write_text('[workspace]\nmembers = ["baseline", "candidate"]\n'
    'resolver = "3"\n[profile.release]\nlto = false\ncodegen-units = 1\n')
lock = root / 'bench/perf/stdlib/results/regex-cardinality-2026-10-29/allocation-Cargo.lock'
(probe / 'Cargo.lock').write_bytes(lock.read_bytes())
```

```sh
cd /tmp/regex-cardinality-alloc
cargo +1.99.1 build --manifest-path /tmp/regex-cardinality-alloc/Cargo.toml --release --locked --workspace --bins
./target/release/alloc-baseline > before.txt
./target/release/alloc-candidate > after.txt
```

Each executable warms each case once, checks every output against independent
expectations, hashes all returned bytes, and prints three trials. Require identical
checksums/case identities and zero `end_extra_live_bytes` for every trial. Alloc and realloc
counts are separate; requested bytes sum full successful request sizes, rather than
net growth. Peak bytes exclude the call-entry heap and allocator metadata and do
not include hidden transient storage within `System::realloc`. The host allocator
and extra atomic instrumentation are why these runs provide allocation evidence,
not generated-program timing.

The header also prints the production-configuration wrapper size and alignment.
The cached flag raises this size from 32 to 40 bytes on the measured x86-64
host. Those persistent eight bytes and the allocation-free metadata scan during
regex construction are excluded from the call counters. No regex-construction
latency or generated-runtime RSS claim is made.

```rust
use regex_under_test::compile;
use std::alloc::{GlobalAlloc, Layout, System};
use std::hint::black_box;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering::Relaxed};

struct CountingAllocator;
static ACTIVE: AtomicBool = AtomicBool::new(false);
static LIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
static ALLOCS: AtomicUsize = AtomicUsize::new(0);
static REALLOCS: AtomicUsize = AtomicUsize::new(0);
static FREES: AtomicUsize = AtomicUsize::new(0);
static REQUESTED: AtomicUsize = AtomicUsize::new(0);

fn added(bytes: usize) {
    let live = LIVE.fetch_add(bytes, Relaxed) + bytes;
    if ACTIVE.load(Relaxed) {
        PEAK.fetch_max(live, Relaxed);
    }
}

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // Safety: the original allocation contract is passed to System unchanged.
        let ptr = unsafe { System.alloc(layout) };
        if !ptr.is_null() {
            added(layout.size());
            if ACTIVE.load(Relaxed) {
                ALLOCS.fetch_add(1, Relaxed);
                REQUESTED.fetch_add(layout.size(), Relaxed);
            }
        }
        ptr
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // Safety: the original allocation contract is passed to System unchanged.
        let ptr = unsafe { System.alloc_zeroed(layout) };
        if !ptr.is_null() {
            added(layout.size());
            if ACTIVE.load(Relaxed) {
                ALLOCS.fetch_add(1, Relaxed);
                REQUESTED.fetch_add(layout.size(), Relaxed);
            }
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        LIVE.fetch_sub(layout.size(), Relaxed);
        if ACTIVE.load(Relaxed) {
            FREES.fetch_add(1, Relaxed);
        }
        // Safety: ptr and layout are forwarded from the caller unchanged.
        unsafe { System.dealloc(ptr, layout) };
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // Safety: ptr, layout and new_size are forwarded unchanged.
        let new_ptr = unsafe { System.realloc(ptr, layout, new_size) };
        if !new_ptr.is_null() {
            if new_size >= layout.size() {
                added(new_size - layout.size());
            } else {
                LIVE.fetch_sub(layout.size() - new_size, Relaxed);
            }
            if ACTIVE.load(Relaxed) {
                REALLOCS.fetch_add(1, Relaxed);
                REQUESTED.fetch_add(new_size, Relaxed);
            }
        }
        new_ptr
    }
}

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

#[derive(Debug, PartialEq, Eq)]
struct Metrics {
    allocs: usize,
    reallocs: usize,
    frees: usize,
    requested_bytes: usize,
    peak_extra_live_bytes: usize,
    end_extra_live_bytes: isize,
    checksum: u64,
}

fn mix(hash: u64, bytes: &[u8]) -> u64 {
    bytes.iter().fold(hash, |h, b| (h ^ u64::from(*b)).wrapping_mul(1099511628211))
}

fn rows_checksum(rows: &[Vec<String>]) -> u64 {
    rows.iter().fold(14695981039346656037, |h, row| {
        let h = row.iter().fold(h, |h, group| mix(mix(h, group.as_bytes()), &[255]));
        mix(h, &[254])
    })
}

fn measured<T>(operation: impl FnOnce() -> T, verify: impl FnOnce(&T) -> u64) -> Metrics {
    let before = LIVE.load(Relaxed);
    for counter in [&ALLOCS, &REALLOCS, &FREES, &REQUESTED] {
        counter.store(0, Relaxed);
    }
    PEAK.store(before, Relaxed);
    ACTIVE.store(true, Relaxed);
    let output = black_box(operation());
    let checksum = black_box(verify(black_box(&output)));
    drop(output);
    ACTIVE.store(false, Relaxed);
    Metrics {
        allocs: ALLOCS.load(Relaxed),
        reallocs: REALLOCS.load(Relaxed),
        frees: FREES.load(Relaxed),
        requested_bytes: REQUESTED.load(Relaxed),
        peak_extra_live_bytes: PEAK.load(Relaxed) - before,
        end_extra_live_bytes: LIVE.load(Relaxed) as isize - before as isize,
        checksum,
    }
}

fn case_rows(name: &str, pattern: &str, text: &str, max: Option<i64>, expected: Vec<Vec<String>>) {
    let re = compile(pattern).unwrap();
    assert_eq!(re.captures_all(text, max).unwrap(), expected);
    let expected_hash = rows_checksum(&expected);
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(|| re.captures_all(black_box(text), max).unwrap(), |rows| {
            assert_eq!(rows, &expected);
            let checksum = rows_checksum(rows);
            assert_eq!(checksum, expected_hash);
            checksum
        });
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("{name}\t{trial}\t{result:?}");
        previous = Some(result);
    }
}

fn case_first(name: &str, pattern: &str, text: &str, expected: Vec<String>) {
    let re = compile(pattern).unwrap();
    assert_eq!(re.captures(text), expected);
    let expected_hash = expected.iter().fold(14695981039346656037, |h, s| mix(mix(h, s.as_bytes()), &[255]));
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(|| re.captures(black_box(text)), |out| {
            assert_eq!(out, &expected);
            let checksum = out.iter().fold(14695981039346656037, |h, s| mix(mix(h, s.as_bytes()), &[255]));
            assert_eq!(checksum, expected_hash);
            checksum
        });
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("{name}\t{trial}\t{result:?}");
        previous = Some(result);
    }
}

fn case_named(name: &str, pattern: &str, text: &str, expected: Vec<(Vec<u8>, Vec<u8>)>) {
    let re = compile(pattern).unwrap();
    assert_eq!(re.named_captures(text), expected);
    let expected_hash = expected.iter().fold(14695981039346656037, |h, (n, v)| mix(mix(mix(h,n), &[255]),v));
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(|| re.named_captures(black_box(text)), |out| {
            assert_eq!(out, &expected);
            let checksum = out.iter().fold(14695981039346656037, |h, (n, v)| mix(mix(mix(h,n), &[255]),v));
            assert_eq!(checksum, expected_hash);
            checksum
        });
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("{name}\t{trial}\t{result:?}");
        previous = Some(result);
    }
}

fn main() {
    println!("variant={} allocator=std::alloc::System baseline=4be5d6d8c warmup=one_per_case trials=3 wrapper_size={} wrapper_align={}", env!("CARGO_PKG_NAME"), core::mem::size_of::<regex_under_test::Regex>(), core::mem::align_of::<regex_under_test::Regex>());
    for count in [0, 1, 128, 2000] {
        let text = "word123 ".repeat(count);
        let expected = (0..count).map(|_| vec!["word123".into()]).collect();
        case_rows(&format!("rows.whole.{count}"), "word[0-9]+", &text, None, expected);
    }
    for count in [1, 2000] {
        let text = "word123 ".repeat(count);
        let expected = (0..count).map(|_| vec!["word123".into(), "word".into(), "123".into()]).collect();
        case_rows(&format!("rows.grouped.{count}"), "(word)([0-9]+)", &text, None, expected);
    }
    case_rows("rows.whole.zero_width_empty", "", "", Some(1), vec![vec!["".into()]]);
    let long = "a".repeat(65536);
    case_rows("rows.whole.long", "a+", &long, Some(1), vec![vec![long.clone()]]);
    case_rows("rows.whole.empty_matches", "a*", "a🙂🙂a", Some(3), vec![vec!["a".into()], vec!["".into()], vec!["a".into()]]);
    let re = compile("word[0-9]+").unwrap();
    let text = "word123 ".repeat(2000);
    assert_eq!(re.captures_all(&text, Some(1)), Err(ms_rt::ffi::Fail::LimitExceeded));
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(|| re.captures_all(black_box(&text), Some(1)), |out| {
            assert_eq!(out, &Err(ms_rt::ffi::Fail::LimitExceeded));
            0
        });
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("rows.whole.over_limit\t{trial}\t{result:?}");
        previous = Some(result);
    }
    let miss = "x".repeat(65536);
    case_rows("rows.whole.miss", "word[0-9]+", &miss, None, vec![]);
    case_first("first.whole.empty_input", "word[0-9]+", "", vec![]);
    case_first("first.whole.zero_width_empty", "", "", vec!["".into()]);
    case_first("first.whole.1", "word[0-9]+", "word123 rest", vec!["word123".into()]);
    case_first("first.whole.long", "a+", &long, vec![long.clone()]);
    case_first("first.whole.miss", "word[0-9]+", &miss, vec![]);
    case_first("first.grouped.1", "(word)([0-9]+)", "word123 rest", vec!["word123".into(), "word".into(), "123".into()]);
    case_named("named.whole.empty_input", "word[0-9]+", "", vec![]);
    case_named("named.whole.zero_width_empty", "", "", vec![]);
    case_named("named.unnamed_grouped.1", "(word)([0-9]+)", "word123", vec![]);
    case_named("named.whole.1", "word[0-9]+", "word123 rest", vec![]);
    case_named("named.whole.long", "a+", &long, vec![]);
    case_named("named.whole.miss", "word[0-9]+", &miss, vec![]);
    case_named("named.grouped.1", "(?P<word>word)([0-9]+)", "word123 rest", vec![(b"word".to_vec(),b"word".to_vec())]);
}
```
