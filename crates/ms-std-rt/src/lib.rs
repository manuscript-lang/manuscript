//! What the `ms-std-*` crates borrow from `ms-rt`: reading and building strings, raising faults and
//! polling cancellation. Everything resolves at the final link against `libms_rt.a`.
#![no_std]
// This crate is the C ABI boundary of the standard-library natives.
#![allow(unsafe_code)]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod pool;

use alloc::vec::Vec;
use core::cell::UnsafeCell;
use core::fmt::{self, Write};
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt_abi::{STATUS_FAILED, StrVal};

unsafe extern "C-unwind" {
    fn msrt_string_from_bytes(ptr: *const u8, len: usize, out: *mut StrVal);
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
    fn msrt_fault(msg: *const u8, len: usize) -> !;
    fn msrt_cancelled() -> !;
    static msrt_cancel_flag: AtomicU8;
}

/// The bytes of a live string.
///
/// # Safety
/// `s` must point to a live `StrVal` whose bytes outlive `'a`.
pub unsafe fn str_bytes<'a>(s: *const StrVal) -> &'a [u8] {
    // SAFETY: `ptr..ptr+len` holds the text.
    unsafe { core::slice::from_raw_parts((*s).ptr, (*s).len) }
}

/// A new owned string (refcount 1) holding `bytes`.
pub fn new_string(bytes: &[u8]) -> StrVal {
    let mut out = core::mem::MaybeUninit::<StrVal>::uninit();
    // SAFETY: the slice is readable; the runtime copies it and writes `out`.
    unsafe {
        msrt_string_from_bytes(bytes.as_ptr(), bytes.len(), out.as_mut_ptr());
        out.assume_init()
    }
}

/// Raises a fault with this message; never returns.
pub fn fault(msg: &str) -> ! {
    // SAFETY: the runtime copies the message.
    unsafe { msrt_fault(msg.as_ptr(), msg.len()) }
}

struct Stack {
    buf: [u8; 512],
    len: usize,
}

impl Write for Stack {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        let n = s.len().min(self.buf.len() - self.len);
        self.buf[self.len..self.len + n].copy_from_slice(&s.as_bytes()[..n]);
        self.len += n;
        Ok(())
    }
}

/// Raises a fault with a formatted message (truncated at 512 bytes); never returns.
pub fn fault_fmt(args: fmt::Arguments<'_>) -> ! {
    let mut s = Stack {
        buf: [0; 512],
        len: 0,
    };
    let _ = s.write_fmt(args);
    // SAFETY: the buffer prefix is readable; the runtime copies it.
    unsafe { msrt_fault(s.buf.as_ptr(), s.len) }
}

/// Whether a stop request (SIGINT or SIGTERM) is pending.
pub fn cancel_pending() -> bool {
    // SAFETY: a plain byte load of the runtime's flag.
    unsafe { msrt_cancel_flag.load(Ordering::Relaxed) != 0 }
}

/// Unwinds the program after a stop request; never returns.
pub fn cancelled() -> ! {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_cancelled() }
}

unsafe extern "C-unwind" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(ptr: *mut u8);
}

unsafe extern "C-unwind" {
    fn msrt_task_sleep(ns: i64) -> u32;
    #[cfg(unix)]
    fn msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32;
}

/// `task_wait_fd` interest and result bits (the runtime's `WAIT_*`).
pub const WAIT_READ: u32 = 1;
pub const WAIT_WRITE: u32 = 2;
pub const WAIT_HUP: u32 = 4;
pub const WAIT_TIMEOUT: u32 = 8;

/// Descriptors a task is parked on. The runtime parks one task per descriptor, so a second
/// task waiting on the same one checks it between short sleeps instead.
#[cfg(unix)]
static PARKED: [core::sync::atomic::AtomicI32; 64] =
    [const { core::sync::atomic::AtomicI32::new(-1) }; 64];

/// Parks the running task until `fd` is ready for `events` (`WAIT_READ`, `WAIT_WRITE`) or the
/// timeout (nanoseconds, negative for none) passes, so other tasks keep running. Returns the
/// ready bits or `WAIT_TIMEOUT`; unwinds the program when a stop request ends the wait.
#[cfg(unix)]
pub fn task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32 {
    /// The runtime's `WAIT_CANCELLED` bit.
    const WAIT_CANCELLED: u32 = 16;
    if PARKED.iter().any(|p| p.load(Ordering::Relaxed) == fd) {
        return wait_fd_in_slices(fd, events, timeout_ns);
    }
    let slot = PARKED.iter().find(|p| {
        p.compare_exchange(-1, fd, Ordering::Relaxed, Ordering::Relaxed)
            .is_ok()
    });
    // SAFETY: parks the current task; no Rust borrow is held across the call.
    let got = unsafe { msrt_task_wait_fd(fd, events, timeout_ns) };
    if let Some(slot) = slot {
        slot.store(-1, Ordering::Relaxed);
    }
    if got & WAIT_CANCELLED != 0 {
        cancelled();
    }
    got
}

/// `task_wait_fd` for a descriptor another task is parked on: checks it every 2 ms.
#[cfg(unix)]
#[allow(
    clippy::unnecessary_cast,
    reason = "timespec fields are not 64-bit on every target"
)]
fn wait_fd_in_slices(fd: i32, events: u32, timeout_ns: i64) -> u32 {
    const SLICE_NS: i64 = 2_000_000;
    let now = || {
        let mut t = libc::timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        // SAFETY: `t` is writable.
        unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t) };
        t.tv_sec as i64 * 1_000_000_000 + t.tv_nsec as i64
    };
    let deadline = (timeout_ns >= 0).then(|| now().saturating_add(timeout_ns));
    let mut p = libc::pollfd {
        fd,
        events: if events & WAIT_WRITE != 0 {
            libc::POLLOUT
        } else {
            libc::POLLIN
        },
        revents: 0,
    };
    loop {
        // SAFETY: `p` is one valid entry.
        if unsafe { libc::poll(&mut p, 1, 0) } > 0 {
            return events;
        }
        let left = deadline.map_or(SLICE_NS, |d| d - now());
        if left <= 0 {
            return WAIT_TIMEOUT;
        }
        task_sleep(left.min(SLICE_NS));
    }
}

/// Parks the running task for `ns` nanoseconds so other tasks keep running, and unwinds the
/// program when a stop request (or task cancellation) ends the wait early.
pub fn task_sleep(ns: i64) {
    /// The runtime's `WAIT_CANCELLED` bit.
    const WAIT_CANCELLED: u32 = 16;
    // SAFETY: parks the current task; no Rust borrow is held across the call.
    if unsafe { msrt_task_sleep(ns) } & WAIT_CANCELLED != 0 {
        cancelled();
    }
}

/// Aborts the program when a stop request is pending (call between blocking steps of long operations).
pub fn poll_cancel() {
    if cancel_pending() {
        cancelled();
    }
}

/// The bytes of a `Bytes` value.
///
/// # Safety
/// `v` must point to a live `VecVal` of bytes.
pub unsafe fn vec_bytes<'a>(v: *const ms_rt_abi::VecVal) -> &'a [u8] {
    // SAFETY: a byte vector is `len` initialised bytes at `ptr` (null when empty).
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr, v.len)
        }
    }
}

/// Initialises `*out` with a fresh `Bytes` copy of `data`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_bytes(data: &[u8], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `data.len()` bytes; the runtime frees it with `msrt_free`.
    unsafe {
        if data.is_empty() {
            *out = ms_rt_abi::VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            return;
        }
        let ptr = msrt_alloc(data.len());
        core::ptr::copy_nonoverlapping(data.as_ptr(), ptr, data.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: data.len(),
            cap: data.len(),
        };
    }
}

/// Initialises `*out` with a `List[String]` that takes ownership of `items`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_string_list(items: &[StrVal], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `items.len()` strings.
    unsafe {
        if items.is_empty() {
            *out = ms_rt_abi::VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            return;
        }
        let ptr = msrt_alloc(core::mem::size_of_val(items));
        core::ptr::copy_nonoverlapping(items.as_ptr(), ptr as *mut StrVal, items.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: items.len(),
            cap: items.len(),
        };
    }
}

unsafe extern "C-unwind" {
    fn msrt_map_new(out: *mut ms_rt_abi::MapVal);
    fn msrt_map_add(
        m: *mut ms_rt_abi::MapVal,
        kd: *const ms_rt_abi::TypeDesc,
        vd: *const ms_rt_abi::TypeDesc,
        key: *mut u8,
        val: *mut u8,
    );
    static msrt_desc_string: ms_rt_abi::TypeDesc;
    static msrt_desc_int: ms_rt_abi::TypeDesc;
}

/// A value of a `Map[String, _]` built by [`write_string_map`].
pub enum MapValue<'a> {
    /// A `String` value.
    Str(&'a [u8]),
    /// An `Int` value.
    Int(i64),
}

/// Initialises `*out` with a `Map[String, String]` (`ints` false) or `Map[String, Int]` (`ints`
/// true) holding `pairs`; the value kind must match `ints`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_string_map<'a>(
    pairs: impl IntoIterator<Item = (&'a [u8], MapValue<'a>)>,
    ints: bool,
    out: *mut ms_rt_abi::MapVal,
) {
    // SAFETY: `out` is writable; each slot holds one owned element for the runtime to take.
    unsafe {
        msrt_map_new(out);
        let vd: *const ms_rt_abi::TypeDesc = if ints {
            &raw const msrt_desc_int
        } else {
            &raw const msrt_desc_string
        };
        for (k, v) in pairs {
            let mut key = new_string(k);
            let kd = &raw const msrt_desc_string;
            match v {
                MapValue::Str(b) => {
                    let mut val = new_string(b);
                    msrt_map_add(out, kd, vd, (&raw mut key).cast(), (&raw mut val).cast());
                }
                MapValue::Int(mut i) => {
                    msrt_map_add(out, kd, vd, (&raw mut key).cast(), (&raw mut i).cast());
                }
            }
        }
    }
}

/// A refcounted runtime object (`Obj` header) wrapping a Rust value; used for handles such as open files.
#[repr(C)]
pub struct Handle<T> {
    pub hdr: ms_rt_abi::Obj,
    pub value: T,
}

unsafe extern "C" fn drop_handle<T>(obj: *mut ms_rt_abi::Obj) {
    // SAFETY: `obj` came from `new_handle::<T>`.
    unsafe {
        core::ptr::drop_in_place(&mut (*(obj as *mut Handle<T>)).value);
        msrt_free(obj as *mut u8);
    }
}

/// Allocates a handle with reference count 1; releasing the last reference drops `value`.
pub fn new_handle<T>(value: T) -> *mut Handle<T> {
    // SAFETY: the block is large and aligned enough for `Handle<T>` (16-byte alignment) and fully initialised.
    unsafe {
        let ptr = msrt_alloc(core::mem::size_of::<Handle<T>>()) as *mut Handle<T>;
        core::ptr::write(
            ptr,
            Handle {
                hdr: ms_rt_abi::Obj {
                    rc: 1,
                    drop: Some(drop_handle::<T>),
                },
                value,
            },
        );
        ptr
    }
}

/// Diagnostic text of the most recent `STATUS_FAILED` result (the runtime is single-threaded).
struct Failure(UnsafeCell<Vec<u8>>);
// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for Failure {}
static FAILURE: Failure = Failure(UnsafeCell::new(Vec::new()));

/// Records the text a later `failure_message` returns.
pub fn record_failure(message: Vec<u8>) {
    // SAFETY: single-threaded runtime; no reference into FAILURE outlives a call.
    unsafe { *FAILURE.0.get() = message };
}

/// Records `message` and returns `STATUS_FAILED`.
pub fn failed(message: &[u8]) -> u8 {
    record_failure(message.to_vec());
    STATUS_FAILED
}

/// A fresh string holding the most recently recorded failure text.
pub fn failure_message() -> StrVal {
    // SAFETY: single-threaded runtime.
    new_string(unsafe { &*FAILURE.0.get() })
}

/// Read-ahead standard input (bytes and the offset of the first unread one) held between handles.
struct StdinPending(UnsafeCell<(Vec<u8>, usize)>);
// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for StdinPending {}

/// Standard-input bytes a dropped `stdin()` handle had read ahead (the runtime is single-threaded).
static STDIN_PENDING: StdinPending = StdinPending(UnsafeCell::new((Vec::new(), 0)));

/// Keeps read-ahead standard input for the next `stdin()` handle: `bytes[head..]` is unread.
///
/// The buffer is handed over without copying unless an earlier stash is still unread.
pub fn stash_stdin_pending(bytes: Vec<u8>, head: usize) {
    // SAFETY: single-threaded runtime; no reference into STDIN_PENDING outlives a call.
    let (held, held_head) = unsafe { &mut *STDIN_PENDING.0.get() };
    if *held_head >= held.len() {
        *held = bytes;
        *held_head = head;
    } else {
        held.extend_from_slice(&bytes[head..]);
    }
}

/// Takes the read-ahead standard input a previous handle left, with the offset of its first unread byte.
pub fn take_stdin_pending() -> (Vec<u8>, usize) {
    // SAFETY: single-threaded runtime.
    unsafe { core::mem::take(&mut *STDIN_PENDING.0.get()) }
}

/// Adds a reference to a runtime object.
///
/// # Safety
/// `o` must point to a live object.
pub unsafe fn retain(o: *mut ms_rt_abi::Obj) {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_retain(o) }
}

/// Drops a reference to a runtime object.
///
/// # Safety
/// `o` must point to a live object the caller holds a reference to.
pub unsafe fn release(o: *mut ms_rt_abi::Obj) {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_release(o) }
}

/// The elements of a list of plain values (`Int`, `Float`, pointers).
///
/// # Safety
/// `v` must point to a live `VecVal` whose elements are `T`.
pub unsafe fn list_slice<'a, T>(v: *const ms_rt_abi::VecVal) -> &'a [T] {
    // SAFETY: a list is `len` initialised elements at `ptr` (null when empty).
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr as *const T, v.len)
        }
    }
}

/// Initialises `*out` with a fresh list holding a copy of `items`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_list<T: Copy>(items: &[T], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `items.len()` elements.
    unsafe {
        if items.is_empty() {
            *out = ms_rt_abi::VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            return;
        }
        let ptr = msrt_alloc(core::mem::size_of_val(items));
        core::ptr::copy_nonoverlapping(items.as_ptr(), ptr as *mut T, items.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: items.len(),
            cap: items.len(),
        };
    }
}
