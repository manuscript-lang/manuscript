//! Windows surface of the runtime: the C runtime for memory and the environment, Win32 for
//! everything else. Declared by hand, with `raw-dylib` imports so the archive needs no import
//! libraries. The same names as the Unix `sys` module where the callers are shared.
#![allow(non_camel_case_types, non_snake_case, clippy::upper_case_acronyms)]

use core::ffi::{c_char, c_int, c_void};

pub type size_t = usize;

pub const STDIN: c_int = 0;
pub const STDOUT: c_int = 1;
pub const STDERR: c_int = 2;

/// Signal numbers of the C runtime; stop requests report them as the exit-status source.
pub const SIGINT: c_int = 2;
pub const SIGTERM: c_int = 15;

pub const O_WRONLY: c_int = 0x1;
pub const O_CREAT: c_int = 0x100;
pub const O_TRUNC: c_int = 0x200;
const O_BINARY: c_int = 0x8000;

type HANDLE = *mut c_void;
type BOOL = i32;
type DWORD = u32;

const MEM_COMMIT: DWORD = 0x1000;
const MEM_RESERVE: DWORD = 0x2000;
const MEM_RELEASE: DWORD = 0x8000;
const PAGE_READWRITE: DWORD = 0x04;
const PAGE_NOACCESS: DWORD = 0x01;
const STD_INPUT_HANDLE: DWORD = -10i32 as DWORD;
const STD_OUTPUT_HANDLE: DWORD = -11i32 as DWORD;
const STD_ERROR_HANDLE: DWORD = -12i32 as DWORD;
const CP_UTF8: u32 = 65001;
const STACK_SIZE_PARAM_IS_A_RESERVATION: DWORD = 0x0001_0000;
const FIBER_FLAG_FLOAT_SWITCH: DWORD = 1;
const INFINITE: DWORD = 0xFFFF_FFFF;

#[link(name = "kernel32", kind = "raw-dylib")]
unsafe extern "system" {
    fn VirtualAlloc(addr: *mut c_void, len: usize, kind: DWORD, protect: DWORD) -> *mut c_void;
    fn VirtualFree(addr: *mut c_void, len: usize, kind: DWORD) -> BOOL;
    fn GetStdHandle(which: DWORD) -> HANDLE;
    fn WriteFile(
        h: HANDLE,
        buf: *const c_void,
        n: DWORD,
        written: *mut DWORD,
        overlapped: *mut c_void,
    ) -> BOOL;
    fn WriteConsoleW(
        h: HANDLE,
        buf: *const u16,
        n: DWORD,
        written: *mut DWORD,
        reserved: *mut c_void,
    ) -> BOOL;
    fn GetConsoleMode(h: HANDLE, mode: *mut DWORD) -> BOOL;
    fn MultiByteToWideChar(
        page: u32,
        flags: DWORD,
        src: *const u8,
        n: i32,
        dst: *mut u16,
        cap: i32,
    ) -> i32;
    fn ExitProcess(code: u32) -> !;
    fn QueryPerformanceCounter(v: *mut i64) -> BOOL;
    fn QueryPerformanceFrequency(v: *mut i64) -> BOOL;
    fn CreateThread(
        attrs: *mut c_void,
        stack: usize,
        start: unsafe extern "system" fn(*mut c_void) -> DWORD,
        arg: *mut c_void,
        flags: DWORD,
        id: *mut DWORD,
    ) -> HANDLE;
    fn WaitForSingleObject(h: HANDLE, ms: DWORD) -> DWORD;
    fn CloseHandle(h: HANDLE) -> BOOL;
    fn Sleep(ms: DWORD);
    fn SetConsoleCtrlHandler(
        handler: Option<unsafe extern "system" fn(DWORD) -> BOOL>,
        add: BOOL,
    ) -> BOOL;
    fn CreateFiberEx(
        commit: usize,
        reserve: usize,
        flags: DWORD,
        start: unsafe extern "system" fn(*mut c_void),
        param: *mut c_void,
    ) -> *mut c_void;
    fn DeleteFiber(fiber: *mut c_void);
    fn SwitchToFiber(fiber: *mut c_void);
    fn ConvertThreadToFiberEx(param: *mut c_void, flags: DWORD) -> *mut c_void;
    fn GetCurrentThreadStackLimits(lo: *mut usize, hi: *mut usize);
    fn GetCurrentProcess() -> HANDLE;
    fn GetCurrentThread() -> HANDLE;
    fn DuplicateHandle(
        src_process: HANDLE,
        src: HANDLE,
        dst_process: HANDLE,
        dst: *mut HANDLE,
        access: DWORD,
        inherit: BOOL,
        options: DWORD,
    ) -> BOOL;
    fn SuspendThread(h: HANDLE) -> DWORD;
    fn ResumeThread(h: HANDLE) -> DWORD;
    fn GetThreadContext(h: HANDLE, ctx: *mut c_void) -> BOOL;
    fn RtlCaptureContext(ctx: *mut c_void);
    fn RtlLookupFunctionEntry(pc: usize, image: *mut usize, history: *mut c_void) -> *mut c_void;
    fn RtlVirtualUnwind(
        kind: u32,
        image: usize,
        pc: usize,
        entry: *mut c_void,
        ctx: *mut c_void,
        handler_data: *mut *mut c_void,
        establisher: *mut usize,
        pointers: *mut c_void,
    ) -> *mut c_void;
}

unsafe extern "C" {
    pub fn malloc(size: size_t) -> *mut c_void;
    pub fn calloc(n: size_t, size: size_t) -> *mut c_void;
    pub fn realloc(p: *mut c_void, size: size_t) -> *mut c_void;
    pub fn free(p: *mut c_void);
    #[link_name = "_msize"]
    fn block_size(p: *mut c_void) -> size_t;
    #[link_name = "_getpid"]
    pub fn getpid() -> c_int;
    #[link_name = "_open"]
    fn crt_open(path: *const c_char, flags: c_int, mode: c_int) -> c_int;
    #[link_name = "_close"]
    pub fn close(fd: c_int) -> c_int;
    #[link_name = "_write"]
    fn crt_write(fd: c_int, buf: *const c_void, n: u32) -> c_int;
    #[link_name = "_errno"]
    fn errno_slot() -> *mut c_int;
    fn getenv(name: *const c_char) -> *const c_char;
    pub fn memcmp(a: *const c_void, b: *const c_void, n: size_t) -> c_int;
}

/// Terminates the process without running cleanup.
///
/// # Safety
/// Nothing runs afterwards; callers have flushed what matters.
pub unsafe fn _exit(code: c_int) -> ! {
    // SAFETY: ends the process.
    unsafe { ExitProcess(code as u32) }
}

pub fn last_errno() -> c_int {
    // SAFETY: the slot function returns the calling thread's errno.
    unsafe { *errno_slot() }
}

/// Opens a file for writing the way the profiler wants it: binary, created, truncated.
///
/// # Safety
/// `path` is NUL terminated.
pub unsafe fn open(path: *const c_char, flags: c_int, mode: c_int) -> c_int {
    // SAFETY: forwarded.
    unsafe { crt_open(path, flags | O_BINARY, mode) }
}

/// Writes a descriptor of the C runtime (used for files the runtime opened itself).
///
/// # Safety
/// `buf` is readable for `n` bytes.
pub unsafe fn write(fd: c_int, buf: *const c_void, n: size_t) -> isize {
    // SAFETY: forwarded; writes are chunked to what the C runtime accepts.
    unsafe { crt_write(fd, buf, n.min(1 << 30) as u32) as isize }
}

/// Usable size of a block from `malloc`/`realloc`.
///
/// # Safety
/// `p` must come from `malloc`, `calloc` or `realloc` and not be freed.
pub unsafe fn malloc_usable_size(p: *mut c_void) -> size_t {
    // SAFETY: forwarded; the caller guarantees a live allocation.
    unsafe { block_size(p) }
}

fn std_handle(fd: c_int) -> HANDLE {
    let which = match fd {
        STDIN => STD_INPUT_HANDLE,
        STDOUT => STD_OUTPUT_HANDLE,
        _ => STD_ERROR_HANDLE,
    };
    // SAFETY: plain Win32 call.
    unsafe { GetStdHandle(which) }
}

/// Whether the standard descriptor is attached to a console.
///
/// # Safety
/// Plain query; unsafe to match the Unix signature.
pub unsafe fn isatty(fd: c_int) -> c_int {
    let mut mode = 0;
    // SAFETY: valid out pointer; an invalid handle just fails.
    (unsafe { GetConsoleMode(std_handle(fd), &mut mode) } != 0) as c_int
}

/// Writes all of `data` to a standard stream. Console output is converted to UTF-16 so text
/// shows correctly whatever the code page; redirected output is the raw bytes.
pub fn write_all(fd: c_int, data: &[u8]) {
    let h = std_handle(fd);
    if h.is_null() || h as isize == -1 {
        return;
    }
    let mut mode = 0;
    // SAFETY: valid out pointer.
    if unsafe { GetConsoleMode(h, &mut mode) } != 0 {
        write_console(h, data);
        return;
    }
    let mut rest = data;
    while !rest.is_empty() {
        let n = rest.len().min(1 << 30) as DWORD;
        let mut done = 0;
        // SAFETY: `rest` is readable for `n` bytes.
        let ok = unsafe { WriteFile(h, rest.as_ptr().cast(), n, &mut done, core::ptr::null_mut()) };
        if ok == 0 || done == 0 {
            return;
        }
        rest = &rest[done as usize..];
    }
}

/// Converts UTF-8 to UTF-16 in chunks and writes it to a console. A multi-byte sequence cut at a
/// chunk end is carried into the next chunk.
fn write_console(h: HANDLE, data: &[u8]) {
    const CHUNK: usize = 4096;
    let mut wide = [0u16; CHUNK];
    let mut rest = data;
    while !rest.is_empty() {
        let mut take = rest.len().min(CHUNK);
        if take < rest.len() {
            // Back up to a character boundary (continuation bytes are 0b10xxxxxx).
            while take > 1 && rest[take] & 0xC0 == 0x80 {
                take -= 1;
            }
        }
        // SAFETY: `wide` holds CHUNK units, enough for CHUNK input bytes.
        let n = unsafe {
            MultiByteToWideChar(
                CP_UTF8,
                0,
                rest.as_ptr(),
                take as i32,
                wide.as_mut_ptr(),
                CHUNK as i32,
            )
        };
        let mut out = &wide[..n.max(0) as usize];
        while !out.is_empty() {
            let mut done = 0;
            // SAFETY: `out` is readable for its length.
            let ok = unsafe {
                WriteConsoleW(
                    h,
                    out.as_ptr(),
                    out.len() as DWORD,
                    &mut done,
                    core::ptr::null_mut(),
                )
            };
            if ok == 0 || done == 0 {
                return;
            }
            out = &out[done as usize..];
        }
        rest = &rest[take..];
    }
}

/// Reads an environment variable as bytes (without the NUL), if set.
pub fn env_var(name: &[u8]) -> Option<&'static [u8]> {
    debug_assert!(name.ends_with(&[0]));
    // SAFETY: `name` is NUL terminated; getenv returns null or a NUL-terminated string that
    // lives for the process (the environment is not modified).
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

/// Reserves `len` bytes of address space; [`commit`] makes ranges of it usable. Null on failure.
pub fn map_anon(len: usize) -> *mut u8 {
    // SAFETY: a fresh reservation.
    unsafe { VirtualAlloc(core::ptr::null_mut(), len, MEM_RESERVE, PAGE_NOACCESS).cast() }
}

/// Commits `len` bytes at `p` (inside a [`map_anon`] reservation) as zeroed read-write memory.
pub fn commit(p: *mut u8, len: usize) -> bool {
    // SAFETY: the range lies inside a reservation of this process.
    !unsafe { VirtualAlloc(p.cast(), len, MEM_COMMIT, PAGE_READWRITE) }.is_null()
}

/// Returns a [`map_anon`] reservation to the system.
///
/// # Safety
/// `p` is the start of a live reservation that nothing uses.
pub unsafe fn unmap(p: *mut u8, _len: usize) {
    // SAFETY: releasing the whole reservation.
    unsafe { VirtualFree(p.cast(), 0, MEM_RELEASE) };
}

/// Monotonic clock in nanoseconds.
pub fn monotonic_ns() -> i64 {
    let (mut freq, mut now) = (0i64, 0i64);
    // SAFETY: valid out pointers; both calls cannot fail on supported Windows versions.
    unsafe {
        QueryPerformanceFrequency(&mut freq);
        QueryPerformanceCounter(&mut now);
    }
    let freq = freq.max(1);
    // Split to avoid overflowing `now * 1e9` after long uptimes.
    (now / freq) * 1_000_000_000 + (now % freq) * 1_000_000_000 / freq
}

pub fn sleep_ms(ms: u32) {
    // SAFETY: plain Win32 call.
    unsafe { Sleep(ms) }
}

/// Starts a thread running `start`. `stack` of 0 takes the default size; otherwise it is the
/// reservation (committed as the stack grows). Null on failure.
///
/// # Safety
/// `start` is a valid thread entry.
pub unsafe fn thread_spawn(
    stack: usize,
    start: unsafe extern "system" fn(*mut c_void) -> u32,
) -> *mut c_void {
    let flags = if stack == 0 {
        0
    } else {
        STACK_SIZE_PARAM_IS_A_RESERVATION
    };
    // SAFETY: forwarded.
    unsafe {
        CreateThread(
            core::ptr::null_mut(),
            stack,
            start,
            core::ptr::null_mut(),
            flags,
            core::ptr::null_mut(),
        )
    }
}

/// Waits for a thread started by [`thread_spawn`] and releases its handle.
///
/// # Safety
/// `thread` is a live handle from `thread_spawn`.
pub unsafe fn thread_join(thread: *mut c_void) {
    // SAFETY: forwarded.
    unsafe {
        WaitForSingleObject(thread, INFINITE);
        CloseHandle(thread);
    }
}

/// Registers `handler` for console control events (Ctrl-C, Ctrl-Break, close, logoff, shutdown).
///
/// # Safety
/// `handler` is a valid handler.
pub unsafe fn set_ctrl_handler(handler: unsafe extern "system" fn(u32) -> i32) {
    // SAFETY: forwarded.
    unsafe { SetConsoleCtrlHandler(Some(handler), 1) };
}

/// Bounds of the current thread's (or fiber's) stack: `(lowest address, one past the highest)`.
pub fn stack_limits() -> (usize, usize) {
    let (mut lo, mut hi) = (0usize, 0usize);
    // SAFETY: valid out pointers.
    unsafe { GetCurrentThreadStackLimits(&mut lo, &mut hi) };
    (lo, hi)
}

// ---- fibers (the stacks of tasks) ----

/// Creates a fiber with `len` bytes of reserved stack that runs `entry` when first switched to.
///
/// # Safety
/// `entry` never returns.
pub unsafe fn fiber_create(len: usize, entry: unsafe extern "system" fn(*mut c_void)) -> *mut u8 {
    // SAFETY: forwarded; the commit size is the platform default.
    unsafe {
        CreateFiberEx(
            0,
            len,
            FIBER_FLAG_FLOAT_SWITCH,
            entry,
            core::ptr::null_mut(),
        )
        .cast()
    }
}

/// # Safety
/// `fiber` is not the running fiber.
pub unsafe fn fiber_delete(fiber: *mut u8) {
    // SAFETY: forwarded.
    unsafe { DeleteFiber(fiber.cast()) };
}

/// Turns the calling thread into a fiber and returns its handle.
///
/// # Safety
/// Called once per thread, before any switch.
pub unsafe fn fiber_adopt() -> *mut u8 {
    // SAFETY: forwarded.
    unsafe { ConvertThreadToFiberEx(core::ptr::null_mut(), FIBER_FLAG_FLOAT_SWITCH).cast() }
}

/// # Safety
/// `fiber` is a live fiber of this thread.
pub unsafe fn fiber_switch(fiber: *mut u8) {
    // SAFETY: forwarded.
    unsafe { SwitchToFiber(fiber.cast()) };
}

// ---- sampling another thread (the profiler) ----

/// Offsets into `CONTEXT` of the instruction pointer and the frame pointer, and its size.
#[cfg(target_arch = "x86_64")]
mod ctx {
    pub const SIZE: usize = 0x4D0;
    pub const FLAGS_OFFSET: usize = 0x30;
    /// `CONTEXT_AMD64 | CONTEXT_CONTROL | CONTEXT_INTEGER`.
    pub const FLAGS: u32 = 0x10_0003;
    pub const PC: usize = 0xF8;
    pub const FP: usize = 0xA0;
    pub const SP: usize = 0x98;
}
#[cfg(target_arch = "aarch64")]
mod ctx {
    pub const SIZE: usize = 0x390;
    pub const FLAGS_OFFSET: usize = 0;
    /// `CONTEXT_ARM64 | CONTEXT_CONTROL | CONTEXT_INTEGER`.
    pub const FLAGS: u32 = 0x40_0003;
    pub const PC: usize = 0x108;
    pub const FP: usize = 0xF0;
    pub const SP: usize = 0x100;
}

#[repr(C, align(16))]
struct Context([u8; ctx::SIZE]);

/// Recovers the first generated source frame through the native fault-reporting
/// prefix. Missing native unwind metadata ends the search: generated glue also
/// lacks it, and must never be mistaken for a native leaf function.
/// Returns `(pc, sp, fp, remaining raw-frame budget)`. Accounting begins with callers
/// of `anchor_pc`; walker-internal frames below that function do not consume it.
pub fn source_frame(
    anchor_pc: usize,
    mut is_source: impl FnMut(usize) -> bool,
) -> Option<(usize, usize, usize, usize)> {
    let mut c = Context([0; ctx::SIZE]);
    let (lo, hi) = stack_limits();
    // SAFETY: aligned, correctly sized architecture-specific CONTEXT. Native
    // unwind records restore all nonvolatile registers; no handlers are invoked.
    unsafe {
        let mut anchor_image = 0;
        let anchor = RtlLookupFunctionEntry(anchor_pc, &mut anchor_image, core::ptr::null_mut());
        if anchor.is_null() {
            return None;
        }
        let mut budget = crate::fault::NativeFrameBudget::default();
        RtlCaptureContext(c.0.as_mut_ptr().cast());
        for _ in 0..256 {
            let word = |off: usize| c.0.as_ptr().add(off).cast::<usize>().read_unaligned();
            let (pc, sp, fp) = (word(ctx::PC), word(ctx::SP), word(ctx::FP));
            if pc == 0 || sp < lo || sp >= hi || !sp.is_multiple_of(8) {
                return None;
            }
            if is_source(pc) {
                // The generated walker consumes this first source frame. A
                // missing anchor must never grant it a fresh/full budget.
                return Some((pc, sp, fp, budget.remaining()?));
            }
            let mut image = 0;
            let entry = RtlLookupFunctionEntry(pc, &mut image, core::ptr::null_mut());
            if entry.is_null() {
                return None;
            }
            // Start at fault_vec, as the Unix frame-pointer walker does. Do not
            // charge the anchor itself: only its recovered callers are visited.
            if !budget.visit(entry == anchor) {
                return None;
            }
            let mut handler = core::ptr::null_mut();
            let mut establisher = 0;
            RtlVirtualUnwind(
                0,
                image,
                pc,
                entry,
                c.0.as_mut_ptr().cast(),
                &mut handler,
                &mut establisher,
                core::ptr::null_mut(),
            );
            let next_sp = c.0.as_ptr().add(ctx::SP).cast::<usize>().read_unaligned();
            let next_pc = c.0.as_ptr().add(ctx::PC).cast::<usize>().read_unaligned();
            if next_sp < sp || (next_sp == sp && next_pc == pc) {
                return None;
            }
        }
    }
    None
}

/// A handle that lets one thread read another's registers.
pub fn current_thread_for_sampling() -> *mut c_void {
    let mut out: HANDLE = core::ptr::null_mut();
    const THREAD_SUSPEND_RESUME_GET_CONTEXT: DWORD = 0x0002 | 0x0008;
    // SAFETY: duplicates the calling thread's pseudo handle into a real one.
    unsafe {
        let me = GetCurrentProcess();
        if DuplicateHandle(
            me,
            GetCurrentThread(),
            me,
            &mut out,
            THREAD_SUSPEND_RESUME_GET_CONTEXT,
            0,
            0,
        ) == 0
        {
            return core::ptr::null_mut();
        }
    }
    out
}

/// Suspends `thread`, reads its `(pc, fp)`, resumes it. `None` when it cannot be read.
///
/// # Safety
/// `thread` is a handle from [`current_thread_for_sampling`] of a live thread other than the caller.
pub unsafe fn sample_thread(thread: *mut c_void) -> Option<(usize, usize)> {
    let mut c = Context([0; ctx::SIZE]);
    // SAFETY: `c` is a correctly sized and aligned CONTEXT for this architecture.
    unsafe {
        c.0.as_mut_ptr()
            .add(ctx::FLAGS_OFFSET)
            .cast::<u32>()
            .write(ctx::FLAGS);
        if SuspendThread(thread) == u32::MAX {
            return None;
        }
        let got = GetThreadContext(thread, c.0.as_mut_ptr().cast()) != 0;
        ResumeThread(thread);
        if !got {
            return None;
        }
        let word = |off: usize| c.0.as_ptr().add(off).cast::<usize>().read_unaligned();
        Some((word(ctx::PC), word(ctx::FP)))
    }
}

/// # Safety
/// `h` is a live handle owned by the caller.
pub unsafe fn close_handle(h: *mut c_void) {
    // SAFETY: the caller owns the handle.
    unsafe { CloseHandle(h) };
}
