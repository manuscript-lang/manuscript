//! Minimal libc surface. Declared by hand so the crate has no dependencies.
#![allow(non_camel_case_types)]

use core::ffi::{c_char, c_int, c_long, c_void};

pub type size_t = usize;

pub const STDIN: c_int = 0;
pub const STDOUT: c_int = 1;
pub const STDERR: c_int = 2;

pub const PROT_READ: c_int = 1;
pub const PROT_WRITE: c_int = 2;
pub const MAP_PRIVATE: c_int = 0x02;
pub const MAP_ANONYMOUS: c_int = 0x20;
pub const MAP_NORESERVE: c_int = 0x4000;

pub const SIGINT: c_int = 2;
pub const SIGALRM: c_int = 14;
pub const SIGTERM: c_int = 15;
pub const SIGPROF: c_int = 27;
pub const SA_SIGINFO: c_int = 4;
pub const SA_RESTART: c_int = 0x1000_0000;
pub const ITIMER_REAL: c_int = 0;
pub const ITIMER_PROF: c_int = 2;

#[repr(C)]
pub struct sigaction_t {
    pub handler: usize,
    pub mask: [u64; 16],
    pub flags: c_int,
    pub restorer: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct timeval {
    pub sec: c_long,
    pub usec: c_long,
}

#[repr(C)]
pub struct itimerval {
    pub interval: timeval,
    pub value: timeval,
}

/// Opaque storage large enough for `pthread_attr_t` on supported targets.
#[repr(C, align(16))]
pub struct pthread_attr_buf(pub [u8; 128]);

unsafe extern "C" {
    pub fn malloc(size: size_t) -> *mut c_void;
    pub fn calloc(n: size_t, size: size_t) -> *mut c_void;
    pub fn realloc(p: *mut c_void, size: size_t) -> *mut c_void;
    pub fn free(p: *mut c_void);
    pub fn malloc_usable_size(p: *mut c_void) -> size_t;
    pub fn write(fd: c_int, buf: *const c_void, n: size_t) -> isize;
    pub fn read(fd: c_int, buf: *mut c_void, n: size_t) -> isize;
    pub fn _exit(code: c_int) -> !;
    pub fn mmap(
        addr: *mut c_void,
        len: size_t,
        prot: c_int,
        flags: c_int,
        fd: c_int,
        off: i64,
    ) -> *mut c_void;
    pub fn getenv(name: *const c_char) -> *const c_char;
    pub fn isatty(fd: c_int) -> c_int;
    pub fn getpid() -> c_int;
    pub fn sigaction(sig: c_int, act: *const sigaction_t, old: *mut sigaction_t) -> c_int;
    pub fn setitimer(which: c_int, new: *const itimerval, old: *mut itimerval) -> c_int;
    pub fn pthread_attr_init(attr: *mut pthread_attr_buf) -> c_int;
    pub fn pthread_attr_setstacksize(attr: *mut pthread_attr_buf, size: size_t) -> c_int;
    pub fn pthread_create(
        thread: *mut usize,
        attr: *const pthread_attr_buf,
        start: extern "C" fn(*mut c_void) -> *mut c_void,
        arg: *mut c_void,
    ) -> c_int;
    pub fn pthread_attr_setstack(
        attr: *mut pthread_attr_buf,
        addr: *mut c_void,
        size: size_t,
    ) -> c_int;
    pub fn mprotect(addr: *mut c_void, len: size_t, prot: c_int) -> c_int;
    pub fn alarm(seconds: u32) -> u32;
    pub fn pthread_join(thread: usize, ret: *mut *mut c_void) -> c_int;
    pub fn open(path: *const c_char, flags: c_int, mode: c_int) -> c_int;
    pub fn close(fd: c_int) -> c_int;
    pub fn memcmp(a: *const c_void, b: *const c_void, n: size_t) -> c_int;
}

pub const O_WRONLY: c_int = 1;
pub const O_CREAT: c_int = 0o100;
pub const O_TRUNC: c_int = 0o1000;

/// Writes all of `data` to `fd`, retrying on partial writes and EINTR.
pub fn write_all(fd: c_int, mut data: &[u8]) {
    while !data.is_empty() {
        // SAFETY: `data` is a valid readable slice for its length.
        let n = unsafe { write(fd, data.as_ptr().cast(), data.len()) };
        if n <= 0 {
            // EINTR retries; any other error drops the output (nothing to report to).
            if n < 0 && last_errno() == 4 {
                continue;
            }
            return;
        }
        data = &data[n as usize..];
    }
}

unsafe extern "C" {
    fn __errno_location() -> *mut c_int;
}

pub fn last_errno() -> c_int {
    // SAFETY: `__errno_location` returns the calling thread's errno slot.
    unsafe { *__errno_location() }
}

/// Reads an environment variable as bytes (without the NUL), if set.
pub fn env_var(name: &[u8]) -> Option<&'static [u8]> {
    debug_assert!(name.ends_with(&[0]));
    // SAFETY: `name` is NUL terminated; getenv returns null or a NUL-terminated
    // string that lives for the process (the environment is not modified).
    unsafe {
        let p = getenv(name.as_ptr().cast());
        if p.is_null() {
            return None;
        }
        let mut n = 0;
        while *p.add(n) != 0 {
            n += 1;
        }
        Some(core::slice::from_raw_parts(p.cast(), n))
    }
}
