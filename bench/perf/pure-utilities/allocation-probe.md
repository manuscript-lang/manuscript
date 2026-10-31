# Native allocation probe

This standalone measurement helper wraps the ordinary system allocator only in
a temporary Rust executable. It measures direct borrowed-input POSIX helpers or
pure component decoding, including destruction of their owned outputs. It does
not instrument MS runtime values or resource mechanisms. It changes no production
allocator. Unsafe code below is only the required `GlobalAlloc` implementation and
unchanged pointer/layout delegation to `System`.

Setup and printing occur with tracking disabled. The single-threaded call loop
validates all fields/error identity and consumes a checked checksum. Every
allocation born during tracking must be destroyed before tracking ends; nonzero
live bytes, counter overflow or underflow rejects the observation. Peak bytes
are requested logical live sizes, excluding allocator metadata, RSS, fragmentation
and transient reallocation overlap. `requested` sums each full request, not growth
deltas. No timing is collected.

For reproduction, extract the Rust fence exactly (including its final newline)
into a temporary standalone Cargo package. Depend on `ms-std-path`, `ms-std-url`
and `ms-rt` from ONE pinned checkout. Use edition `2024`, release panic=abort,
checked workload arithmetic and native release dependency arithmetic. Build
with explicit `--manifest-path` AND `--target-dir`; consume Cargo's reported
executable from that target directory. Record source/manifest/lock/binary hashes.

The first normalization count replay copied a stale executable from a different
target directory. Its dataset is preserved as **invalid provenance**, excluded
from all claims. The corrected replay of 776 observations uses explicit targets, matches
source/binary identities and confirms two fewer nonempty-normalize allocations.

Arguments: operation count input status field0 field1 field2 field3 field4.
Operations: path-extension, path-parse, path-normalize, url-decode. Status is
OK or InvalidData; unused fields are empty. Output columns are operation, count,
checksum, allocation calls, reallocation calls, cumulative requested bytes,
peak requested live bytes, final live bytes. Repeat `count=1`/`count=100` twice in
fresh processes: totals must scale and per-call peaks stay constant.

Extracted source SHA-256: `3680ca135926b5b7c4e741ade5e6b4ddd65db3171c1201a12aacb548ca3109b8`.

```rust
//! Counts direct native helper allocations, including destruction, not MS lifetimes.
use std::{alloc::{GlobalAlloc, Layout, System}, hint::black_box, sync::atomic::{AtomicBool, AtomicUsize, Ordering}};
use ms_rt::ffi::Fail;

struct CountedSystem;
static TRACK: AtomicBool = AtomicBool::new(false);
static ALLOC_CALLS: AtomicUsize = AtomicUsize::new(0);
static REALLOC_CALLS: AtomicUsize = AtomicUsize::new(0);
static REQUESTED: AtomicUsize = AtomicUsize::new(0);
static LIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
static BAD_ACCOUNTING: AtomicBool = AtomicBool::new(false);

fn add_live(size: usize) {
    let old = LIVE.fetch_add(size, Ordering::Relaxed);
    if let Some(now) = old.checked_add(size) { PEAK.fetch_max(now, Ordering::Relaxed); }
    else { BAD_ACCOUNTING.store(true, Ordering::Relaxed); }
}
fn sub_live(size: usize) {
    let old = LIVE.fetch_sub(size, Ordering::Relaxed);
    if old < size { BAD_ACCOUNTING.store(true, Ordering::Relaxed); }
}
fn add_requested(size: usize) {
    let old = REQUESTED.fetch_add(size, Ordering::Relaxed);
    if old.checked_add(size).is_none() { BAD_ACCOUNTING.store(true, Ordering::Relaxed); }
}
// Unsafe is confined to the required GlobalAlloc interface and delegation to
// System with unchanged pointers/layouts. Counters allocate no memory.
unsafe impl GlobalAlloc for CountedSystem {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let active = TRACK.load(Ordering::Relaxed);
        if active { ALLOC_CALLS.fetch_add(1, Ordering::Relaxed); add_requested(layout.size()); }
        let ptr = unsafe { System.alloc(layout) };
        if active && !ptr.is_null() { add_live(layout.size()); }
        ptr
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let active = TRACK.load(Ordering::Relaxed);
        if active { ALLOC_CALLS.fetch_add(1, Ordering::Relaxed); add_requested(layout.size()); }
        let ptr = unsafe { System.alloc_zeroed(layout) };
        if active && !ptr.is_null() { add_live(layout.size()); }
        ptr
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if TRACK.load(Ordering::Relaxed) { sub_live(layout.size()); }
        unsafe { System.dealloc(ptr, layout) };
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let active = TRACK.load(Ordering::Relaxed);
        if active { REALLOC_CALLS.fetch_add(1, Ordering::Relaxed); add_requested(size); }
        let result = unsafe { System.realloc(ptr, layout, size) };
        if active && !result.is_null() {
            // Logical requested live bytes; not allocator-internal transient memory.
            sub_live(layout.size()); add_live(size);
        }
        result
    }
}
#[global_allocator]
static ALLOCATOR: CountedSystem = CountedSystem;

#[inline(never)]
fn operation(op: &str, input: &str, status: &str, expected: &[String]) -> usize {
    match op {
        "path-extension" => {
            let output = ms_std_path::POSIX.extension(black_box(input));
            assert_eq!(status, "OK"); assert_eq!(output, expected[0]);
            black_box(&output); output.len()
        }
        "path-normalize" => {
            let output = ms_std_path::POSIX.normalize(black_box(input));
            assert_eq!(status, "OK"); assert_eq!(output, expected[0]);
            black_box(&output); output.len()
        }
        "path-parse" => {
            let output = ms_std_path::POSIX.parse(black_box(input));
            assert_eq!(status, "OK");
            let actual = [&output.root, &output.directory, &output.base, &output.extension, &output.name];
            let mut checksum = 0usize;
            for (actual, expected) in actual.into_iter().zip(expected) {
                assert_eq!(actual, expected);
                checksum = checksum.checked_add(actual.len()).expect("checksum overflow");
            }
            black_box(&output); checksum
        }
        "url-decode" => {
            let output = ms_std_url::decode_component(black_box(input));
            black_box(&output);
            if let Err(error) = &output {
                assert_eq!(status, "InvalidData"); assert_eq!(*error, Fail::InvalidData);
                return 1;
            }
            let output = output.unwrap();
            assert_eq!(status, "OK"); assert_eq!(output, expected[0]); output.len()
        }
        _ => unreachable!(),
    }
}
fn main() {
    // Args and expected strings are owned before tracking; helpers borrow input.
    // op count input status field0 field1 field2 field3 field4
    let args: Vec<String> = std::env::args().skip(1).collect();
    assert_eq!(args.len(), 9);
    let op = &args[0];
    assert!(["path-extension", "path-parse", "path-normalize", "url-decode"].contains(&op.as_str()));
    let count: usize = args[1].parse().unwrap(); assert!(count > 0);
    let input = &args[2]; let status = &args[3]; let expected = &args[4..9];
    assert!(status == "OK" || status == "InvalidData");
    if op != "url-decode" { assert_eq!(status, "OK"); }
    if op != "path-parse" { assert!(expected[1..].iter().all(String::is_empty)); }
    if status == "InvalidData" { assert!(expected.iter().all(String::is_empty)); }
    let per_operation = if status == "InvalidData" { 1 } else {
        expected.iter().try_fold(0usize, |sum, s| sum.checked_add(s.len())).unwrap()
    };
    let expected_checksum = per_operation.checked_mul(count).expect("checksum overflow");
    // No warm call: first-call behavior is included. No printing/setup runs tracked.
    TRACK.store(true, Ordering::SeqCst);
    let mut checksum = 0usize;
    for _ in 0..count {
        checksum = checksum.checked_add(operation(op, input, status, expected)).expect("checksum overflow");
    }
    black_box(checksum);
    TRACK.store(false, Ordering::SeqCst);
    let allocations = ALLOC_CALLS.load(Ordering::Relaxed);
    let reallocations = REALLOC_CALLS.load(Ordering::Relaxed);
    let requested = REQUESTED.load(Ordering::Relaxed);
    let peak = PEAK.load(Ordering::Relaxed);
    let live = LIVE.load(Ordering::Relaxed);
    assert!(!BAD_ACCOUNTING.load(Ordering::Relaxed), "tracking crossed an allocation boundary or overflowed");
    assert_eq!(checksum, expected_checksum);
    // Helpers in this scope must not retain allocations after returned outputs drop.
    assert_eq!(live, 0, "native helper retained allocation beyond the tracking interval");
    println!("{op}\t{count}\t{checksum}\t{allocations}\t{reallocations}\t{requested}\t{peak}\t{live}");
}
```
