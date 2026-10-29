# Reproduce the regex allocation diagnostic

This external-only host Rust harness forwards the global allocator to `System`
and counts allocation requests and logical live sizes around one regex call,
complete output checks, and destruction. It does not instrument the Manuscript
runtime allocator or measure RSS. See [the result report](regex-results-2026-10-29.md).

Save the Rust fence below as `/tmp/regex-alloc/harness.rs`. Run this setup from
the candidate repository root; it copies just the regex sources into temporary
packages and uses unchanged runtime path dependencies. The baseline regex sources
are byte-identical at `4c0a1cb8` and `7e2e62357`.

```python
from pathlib import Path
import json
import subprocess

root = Path.cwd().resolve()
probe = Path('/tmp/regex-alloc')
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
                f'7e2e62357d5cebc1f144b6ee86f38da247cd2f52:{path}'])
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
```

```sh
cd /tmp/regex-alloc
cargo +1.99.1 build --release --workspace --bins
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

```rust
use regex_under_test::{Regex, compile};
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

fn capture_case(count: usize) {
    let re = compile("(word)([0-9]+)").unwrap();
    let text = "word123 ".repeat(count);
    let expected: Vec<Vec<String>> = (0..count)
        .map(|_| vec!["word123".into(), "word".into(), "123".into()])
        .collect();
    assert_eq!(re.captures_all(&text, None).unwrap(), expected);
    let expected_hash = rows_checksum(&expected);
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(
            || re.captures_all(black_box(&text), None).unwrap(),
            |rows| {
                assert_eq!(rows, &expected);
                let checksum = rows_checksum(rows);
                assert_eq!(checksum, expected_hash);
                checksum
            },
        );
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("captures_all.{count}\t{trial}\t{result:?}");
        previous = Some(result);
    }
}

fn template_case(name: &str, re: &Regex, text: &str, template: &str, expected: &str) {
    assert_eq!(re.replace_template(text, template, None).unwrap(), expected);
    let expected_hash = mix(14695981039346656037, expected.as_bytes());
    let mut previous = None;
    for trial in 0..3 {
        let result = measured(
            || re.replace_template(black_box(text), black_box(template), None).unwrap(),
            |out| {
                assert_eq!(out, expected);
                let checksum = mix(14695981039346656037, out.as_bytes());
                assert_eq!(checksum, expected_hash);
                checksum
            },
        );
        assert_eq!(result.end_extra_live_bytes, 0);
        if let Some(previous) = &previous { assert_eq!(&result, previous); }
        println!("{name}\t{trial}\t{result:?}");
        previous = Some(result);
    }
}

fn main() {
    println!("variant={} allocator=std::alloc::System counters=successful_alloc_realloc_requests warmup=one_per_case trials=3", env!("CARGO_PKG_NAME"));
    for count in [0, 1, 128, 2000] {
        capture_case(count);
        let re = compile("(?P<word>word)([0-9]+)").unwrap();
        let text = "word123 ".repeat(count);
        let expected = "123:word$ ".repeat(count);
        template_case(&format!("replace_template.{count}"), &re, &text, "$2:${word}$$", &expected);
    }
    let re = compile("(?P<part>a+)").unwrap();
    let long = "a".repeat(65536);
    let text = format!("{long}{}", " a".repeat(1999));
    let expected = format!("{long}:{long}${}", " a:a$".repeat(1999));
    template_case("replace_template.mixed_long_short.2000", &re, &text, "${part}:$0$$", &expected);
    for count in [0, 1, 2000] {
        let re = compile("(word)([0-9]+)").unwrap();
        let text = "word123 ".repeat(count);
        let expected = "fixed ".repeat(count);
        template_case(&format!("replace_template.literal.{count}"), &re, &text, "fixed", &expected);
    }
    let re = compile("x").unwrap();
    let unused = "a".repeat(2_000_000);
    template_case("replace_template.unused_large", &re, "z", &unused, "z");
}

```
