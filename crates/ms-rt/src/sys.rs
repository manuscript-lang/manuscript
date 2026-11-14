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
#[cfg(target_os = "macos")]
pub const MAP_ANONYMOUS: c_int = 0x1000;
#[cfg(target_os = "macos")]
pub const MAP_NORESERVE: c_int = 0x40;
#[cfg(not(target_os = "macos"))]
pub const MAP_ANONYMOUS: c_int = 0x20;
#[cfg(not(target_os = "macos"))]
pub const MAP_NORESERVE: c_int = 0x4000;

pub const EINTR: c_int = 4;
#[cfg(target_os = "macos")]
pub const EAGAIN: c_int = 35;
#[cfg(not(target_os = "macos"))]
pub const EAGAIN: c_int = 11;

pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;
#[cfg(target_os = "macos")]
pub const O_NONBLOCK: c_int = 0x4;
#[cfg(not(target_os = "macos"))]
pub const O_NONBLOCK: c_int = 0o4000;

pub const SIGINT: c_int = 2;
pub const SIGPIPE: c_int = 13;
/// `SIG_IGN` as a `sigaction` handler value.
pub const SIG_IGN: usize = 1;
pub const SIGALRM: c_int = 14;
pub const SIGTERM: c_int = 15;
pub const SIGPROF: c_int = 27;
pub const SIGSEGV: c_int = 11;
#[cfg(target_os = "macos")]
pub const SIGBUS: c_int = 10;
#[cfg(not(target_os = "macos"))]
pub const SIGBUS: c_int = 7;
#[cfg(target_os = "macos")]
pub const SA_ONSTACK: c_int = 0x1;
#[cfg(not(target_os = "macos"))]
pub const SA_ONSTACK: c_int = 0x0800_0000;
/// Offset of `si_addr` in `siginfo_t`.
#[cfg(target_os = "macos")]
pub const SI_ADDR_OFFSET: usize = 24;
#[cfg(not(target_os = "macos"))]
pub const SI_ADDR_OFFSET: usize = 16;
#[cfg(target_os = "macos")]
pub const SA_SIGINFO: c_int = 0x40;
#[cfg(target_os = "macos")]
pub const SA_RESTART: c_int = 0x2;
#[cfg(not(target_os = "macos"))]
pub const SA_SIGINFO: c_int = 4;
#[cfg(not(target_os = "macos"))]
pub const SA_RESTART: c_int = 0x1000_0000;
pub const ITIMER_REAL: c_int = 0;
pub const ITIMER_PROF: c_int = 2;

/// glibc's `struct sigaction`.
#[cfg(not(target_os = "macos"))]
#[repr(C)]
pub struct sigaction_t {
    handler: usize,
    mask: [u64; 16],
    flags: c_int,
    restorer: usize,
}

/// macOS's `struct sigaction`.
#[cfg(target_os = "macos")]
#[repr(C)]
pub struct sigaction_t {
    handler: usize,
    mask: u32,
    flags: c_int,
}

/// `stack_t`: an alternate signal stack.
#[cfg(not(target_os = "macos"))]
#[repr(C)]
pub struct stack_t {
    pub ss_sp: *mut c_void,
    pub ss_flags: c_int,
    pub ss_size: size_t,
}

/// `stack_t`: an alternate signal stack.
#[cfg(target_os = "macos")]
#[repr(C)]
pub struct stack_t {
    pub ss_sp: *mut c_void,
    pub ss_size: size_t,
    pub ss_flags: c_int,
}

impl sigaction_t {
    /// A disposition running `handler` with no signals blocked and the given `SA_*` flags.
    pub fn new(handler: usize, flags: c_int) -> sigaction_t {
        #[cfg(not(target_os = "macos"))]
        return sigaction_t {
            handler,
            mask: [0; 16],
            flags,
            restorer: 0,
        };
        #[cfg(target_os = "macos")]
        return sigaction_t {
            handler,
            mask: 0,
            flags,
        };
    }
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
    pub fn sigaltstack(new: *const stack_t, old: *mut stack_t) -> c_int;
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
    pub fn open(path: *const c_char, flags: c_int, ...) -> c_int;
    pub fn close(fd: c_int) -> c_int;
    pub fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    pub fn fork() -> c_int;
    pub fn pipe(fds: *mut c_int) -> c_int;
    pub fn dup2(from: c_int, to: c_int) -> c_int;
    pub fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
    pub fn memcmp(a: *const c_void, b: *const c_void, n: size_t) -> c_int;
}

pub const O_WRONLY: c_int = 1;
#[cfg(target_os = "macos")]
pub const O_CREAT: c_int = 0x200;
#[cfg(target_os = "macos")]
pub const O_TRUNC: c_int = 0x400;
#[cfg(not(target_os = "macos"))]
pub const O_CREAT: c_int = 0o100;
#[cfg(not(target_os = "macos"))]
pub const O_TRUNC: c_int = 0o1000;

/// Writes all of `data` to `fd`, retrying on partial writes and EINTR; returns 0, or the error code of the failed write.
pub fn write_all(fd: c_int, mut data: &[u8]) -> c_int {
    while !data.is_empty() {
        // SAFETY: `data` is a valid readable slice for its length.
        let n = unsafe { write(fd, data.as_ptr().cast(), data.len()) };
        if n <= 0 {
            // EINTR retries; any other failure returns its code (EIO when nothing was written
            // and no code was set).
            if n < 0 && last_errno() == 4 {
                continue;
            }
            return if n < 0 { last_errno() } else { 5 };
        }
        data = &data[n as usize..];
    }
    0
}

/// Whether a write failure means the reader went away (`EPIPE`): a program piped into `head`
/// ends quietly instead of reporting it.
pub fn is_broken_pipe(code: c_int) -> bool {
    code == 32
}

unsafe extern "C" {
    #[cfg(target_os = "macos")]
    #[link_name = "__error"]
    fn errno_slot() -> *mut c_int;
    #[cfg(not(target_os = "macos"))]
    #[link_name = "__errno_location"]
    fn errno_slot() -> *mut c_int;
    #[cfg(target_os = "macos")]
    #[link_name = "malloc_size"]
    fn block_size(p: *const c_void) -> size_t;
    #[cfg(not(target_os = "macos"))]
    #[link_name = "malloc_usable_size"]
    fn block_size(p: *mut c_void) -> size_t;
}

pub fn last_errno() -> c_int {
    // SAFETY: the slot function returns the calling thread's errno.
    unsafe { *errno_slot() }
}

/// Usable size of a block from `malloc`/`realloc`.
///
/// # Safety
/// `p` must come from `malloc`, `calloc` or `realloc` and not be freed.
pub unsafe fn malloc_usable_size(p: *mut c_void) -> size_t {
    // SAFETY: forwarded; the caller guarantees a live allocation.
    unsafe { block_size(p) }
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

#[cfg(miri)]
pub fn map_anon(len: usize) -> *mut u8 {
    // Miri has no `mmap`; a zeroed heap block stands in so the allocator can be checked.
    let layout = core::alloc::Layout::from_size_align(len, 1 << 16).unwrap();
    // SAFETY: `len` is nonzero.
    unsafe { stdalloc::alloc::alloc_zeroed(layout) }
}

/// Reserves `len` bytes of zeroed address space; [`commit`] makes ranges of it usable. Null on failure.
#[cfg(not(miri))]
pub fn map_anon(len: usize) -> *mut u8 {
    // SAFETY: anonymous private mapping; failure is reported as MAP_FAILED.
    let p = unsafe {
        mmap(
            core::ptr::null_mut(),
            len,
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE,
            -1,
            0,
        )
    };
    if p as isize == -1 {
        core::ptr::null_mut()
    } else {
        p.cast()
    }
}

/// Asks Linux to back a heap reservation with huge pages where it can: a program that builds
/// megabytes of cells takes a page fault per 4 KiB otherwise.
///
/// macOS and Windows have no equivalent for a lazily committed reservation of this size: macOS
/// superpages (`VM_FLAGS_SUPERPAGE_SIZE_2MB`) exist only on Intel, are wired and physically
/// contiguous, and cannot back a 256 GiB reservation; Apple Silicon uses 16 KiB base pages. Windows
/// large pages (`MEM_LARGE_PAGES`) need the `SeLockMemoryPrivilege` right, which a normal user
/// does not hold, and are not demand-committed. Both stay no-ops (#3710).
#[cfg(all(target_os = "linux", not(miri)))]
pub fn prefer_huge_pages(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn madvise(addr: *mut c_void, len: size_t, advice: c_int) -> c_int;
    }
    const MADV_HUGEPAGE: c_int = 14;
    // SAFETY: advice only; `p..p+len` is a mapping of this process.
    unsafe { madvise(p.cast(), len, MADV_HUGEPAGE) };
}

#[cfg(not(all(target_os = "linux", not(miri))))]
pub fn prefer_huge_pages(_p: *mut u8, _len: usize) {}

/// Reserves `len` bytes of address space aligned to `len` (a power of two), holding stacks: no
/// huge pages, so a touched stack page costs one page and not two megabytes. Null on failure.
pub fn map_region(len: usize) -> *mut u8 {
    let raw = map_anon(2 * len);
    if raw.is_null() {
        return raw;
    }
    let start = raw as usize;
    let base = start.next_multiple_of(len);
    // SAFETY: trims the unaligned head and tail of the fresh reservation.
    unsafe {
        if base > start {
            unmap(start as *mut u8, base - start);
        }
        let end = start + 2 * len;
        if end > base + len {
            unmap((base + len) as *mut u8, end - base - len);
        }
        #[cfg(target_os = "linux")]
        {
            unsafe extern "C" {
                fn madvise(addr: *mut c_void, len: size_t, advice: c_int) -> c_int;
            }
            const MADV_NOHUGEPAGE: c_int = 15;
            madvise(base as *mut c_void, len, MADV_NOHUGEPAGE);
        }
    }
    base as *mut u8
}

/// Makes `len` bytes at `p` (inside a [`map_anon`] mapping) usable. Unix maps everything readable
/// and writable up front and the kernel commits pages on first touch.
pub fn commit(_p: *mut u8, _len: usize) -> bool {
    true
}

/// A guard page below a stack's committed pages: nothing to do on Unix, where the kernel
/// commits any page of the mapping on first touch.
pub fn commit_guard(_p: *mut u8) -> bool {
    true
}

/// Gives the pages of `len` bytes at `p` (inside a [`map_anon`] mapping) back to the system.
/// They need no [`commit`] again on Unix. What they read as is unspecified: Linux zero-fills them,
/// but macOS frees them lazily and may keep the old contents.
///
/// # Safety
/// The range lies inside a live mapping and holds nothing in use.
pub unsafe fn release(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn madvise(addr: *mut c_void, len: size_t, advice: c_int) -> c_int;
    }
    #[cfg(target_os = "macos")]
    const MADV_DONTNEED: c_int = 5; // MADV_FREE: macOS leaves MADV_DONTNEED a no-op
    #[cfg(not(target_os = "macos"))]
    const MADV_DONTNEED: c_int = 4;
    if !cfg!(miri) {
        // SAFETY: forwarded; the caller guarantees the range.
        unsafe { madvise(p.cast(), len, MADV_DONTNEED) };
    }
}

/// Makes `len` bytes at `p` inaccessible (a stack guard). Linux 6.13 and later install a guard
/// region, which splits no mapping, so guards cost nothing however many stacks there are. Older
/// kernels and macOS fall back to `mprotect`, which splits the mapping: false when the kernel
/// refuses, which happens once the process has used up its memory mappings
/// (`vm.max_map_count`), and a stack without its guard must not be used.
///
/// # Safety
/// The range lies inside a live mapping that nothing is using.
pub unsafe fn guard(p: *mut u8, len: usize) -> bool {
    #[cfg(target_os = "linux")]
    {
        unsafe extern "C" {
            fn madvise(addr: *mut c_void, len: size_t, advice: c_int) -> c_int;
        }
        const MADV_GUARD_INSTALL: c_int = 102;
        // SAFETY: forwarded; the caller guarantees the range.
        if unsafe { madvise(p.cast(), len, MADV_GUARD_INSTALL) } == 0 {
            return true;
        }
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { mprotect(p.cast(), len, 0) == 0 }
}

/// Returns a [`map_anon`] mapping to the system.
///
/// # Safety
/// The mapping is live and unused.
pub unsafe fn unmap(p: *mut u8, len: usize) {
    unsafe extern "C" {
        fn munmap(addr: *mut c_void, len: size_t) -> c_int;
    }
    // SAFETY: forwarded; the caller guarantees the range.
    unsafe { munmap(p.cast(), len) };
}

#[repr(C)]
struct Timespec {
    sec: i64,
    nsec: i64,
}

unsafe extern "C" {
    fn clock_gettime(clock: c_int, ts: *mut Timespec) -> c_int;
}

#[cfg(target_os = "macos")]
const CLOCK_MONOTONIC: c_int = 6;
#[cfg(not(target_os = "macos"))]
const CLOCK_MONOTONIC: c_int = 1;

/// Monotonic clock in nanoseconds.
pub fn monotonic_ns() -> i64 {
    let mut t = Timespec { sec: 0, nsec: 0 };
    // SAFETY: valid out pointer.
    unsafe { clock_gettime(CLOCK_MONOTONIC, &mut t) };
    t.sec * 1_000_000_000 + t.nsec
}
