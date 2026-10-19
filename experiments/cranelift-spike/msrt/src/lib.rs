//! Runtime linked into every program `msc` builds: faults, allocation,
//! cancellation, the Int map, and the benchmark clock and report.
//!
//! `no_std` over libc keeps the archive small, so linking stays fast.

#![no_std]

extern crate alloc;

use alloc::vec;
use alloc::vec::Vec;
use core::alloc::{GlobalAlloc, Layout};
use core::sync::atomic::AtomicI32;

extern "C" {
    fn malloc(size: usize) -> *mut u8;
    fn realloc(p: *mut u8, size: usize) -> *mut u8;
    fn free(p: *mut u8);
    fn write(fd: i32, buf: *const u8, len: usize) -> isize;
    fn exit(code: i32) -> !;
    fn abort() -> !;
    fn clock_gettime(clock: i32, ts: *mut Timespec) -> i32;
}

#[repr(C)]
struct Timespec {
    sec: i64,
    nsec: i64,
}

struct Malloc;

unsafe impl GlobalAlloc for Malloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        malloc(layout.size())
    }
    unsafe fn dealloc(&self, p: *mut u8, _: Layout) {
        free(p)
    }
    unsafe fn realloc(&self, p: *mut u8, _: Layout, size: usize) -> *mut u8 {
        realloc(p, size)
    }
}

#[global_allocator]
static ALLOCATOR: Malloc = Malloc;

/// The precompiled `alloc` crate references the unwinding personality; panics
/// abort, so it is never called.
#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    unsafe { abort() }
}

fn put(fd: i32, bytes: &[u8]) {
    unsafe { write(fd, bytes.as_ptr(), bytes.len()) };
}

fn put_int(out: &mut Vec<u8>, v: i64) {
    if v < 0 {
        out.push(b'-');
    }
    let mut digits = [0u8; 20];
    let mut n = v.unsigned_abs();
    let mut i = digits.len();
    loop {
        i -= 1;
        digits[i] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(&digits[i..]);
}

/// Set when the enclosing work is cancelled; generated loops poll it.
#[no_mangle]
pub static msrt_cancelled: AtomicI32 = AtomicI32::new(0);

const FAULTS: [&str; 6] = ["Int overflow", "division by zero", "index out of range", "cancelled", "out of memory", "unreachable"];

#[no_mangle]
pub extern "C" fn msrt_fault(code: i64) -> ! {
    let what = FAULTS.get(code as usize).copied().unwrap_or("unknown fault");
    put(2, b"fault: ");
    put(2, what.as_bytes());
    put(2, b"\n");
    unsafe { exit(2) }
}

#[no_mangle]
pub unsafe extern "C" fn msrt_alloc(size: i64) -> *mut u8 {
    let p = malloc(size as usize);
    if p.is_null() {
        msrt_fault(4)
    }
    p
}

#[no_mangle]
pub unsafe extern "C" fn msrt_free(p: *mut u8) {
    free(p)
}

/// Grows a list buffer to `cap` elements of `elem` bytes; null `p` allocates.
#[no_mangle]
pub unsafe extern "C" fn msrt_grow(p: *mut u8, cap: i64, elem: i64) -> *mut u8 {
    let q = realloc(p, (cap * elem) as usize);
    if q.is_null() {
        msrt_fault(4)
    }
    q
}

/// Map[Int, Int]: insertion-ordered compact dict (dense entries plus an
/// open-addressing index), matching Manuscript's ordered Map contract.
pub struct IntMap {
    entries: Vec<(i64, i64)>,
    index: Vec<i32>,
}

fn hash(k: i64) -> u64 {
    let mut z = (k as u64).wrapping_add(0x9e3779b97f4a7c15);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}

impl IntMap {
    fn slot(&self, key: i64) -> usize {
        let mask = self.index.len() - 1;
        let mut h = hash(key) as usize & mask;
        loop {
            let e = self.index[h];
            if e < 0 || self.entries[e as usize].0 == key {
                return h;
            }
            h = (h + 1) & mask;
        }
    }

    fn grow(&mut self) {
        let slots = self.index.len() * 2;
        self.index = vec![-1; slots];
        for (e, &(k, _)) in self.entries.iter().enumerate() {
            let mut h = hash(k) as usize & (slots - 1);
            while self.index[h] >= 0 {
                h = (h + 1) & (slots - 1);
            }
            self.index[h] = e as i32;
        }
    }
}

#[no_mangle]
pub extern "C" fn msrt_map_new() -> *mut IntMap {
    alloc::boxed::Box::into_raw(alloc::boxed::Box::new(IntMap { entries: Vec::new(), index: vec![-1; 8] }))
}

#[no_mangle]
pub unsafe extern "C" fn msrt_map_free(m: *mut IntMap) {
    drop(alloc::boxed::Box::from_raw(m));
}

/// Returns 1 and writes the value when `key` is present, else 0.
#[no_mangle]
pub unsafe extern "C" fn msrt_map_get(m: *const IntMap, key: i64, out: *mut i64) -> i8 {
    let m = &*m;
    let e = m.index[m.slot(key)];
    if e < 0 {
        return 0;
    }
    out.write(m.entries[e as usize].1);
    1
}

#[no_mangle]
pub unsafe extern "C" fn msrt_map_add(m: *mut IntMap, key: i64, value: i64) {
    let m = &mut *m;
    let h = m.slot(key);
    let e = m.index[h];
    if e >= 0 {
        m.entries[e as usize].1 = value;
        return;
    }
    m.index[h] = m.entries.len() as i32;
    m.entries.push((key, value));
    if m.entries.len() * 4 >= m.index.len() * 3 {
        m.grow();
    }
}

#[no_mangle]
pub unsafe extern "C" fn msrt_map_len(m: *const IntMap) -> i64 {
    (*m).entries.len() as i64
}

#[no_mangle]
pub extern "C" fn msrt_now_us() -> i64 {
    let mut ts = Timespec { sec: 0, nsec: 0 };
    unsafe { clock_gettime(1, &mut ts) }; // CLOCK_MONOTONIC
    ts.sec * 1_000_000 + ts.nsec / 1000
}

#[no_mangle]
pub unsafe extern "C" fn msrt_report(name: *const u8, len: i64, micros: i64, result: i64) {
    let mut line = Vec::with_capacity(64);
    line.extend_from_slice(core::slice::from_raw_parts(name, len as usize));
    line.push(b' ');
    put_int(&mut line, micros);
    line.push(b' ');
    put_int(&mut line, result);
    line.push(b'\n');
    put(1, &line);
}

extern "C" {
    fn ms_main() -> i64;
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    unsafe { ms_main() as i32 }
}
