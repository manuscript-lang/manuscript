//! Sampling profiler: `MS_PROFILE=<path>` writes folded stacks at exit.
//!
//! `ITIMER_PROF` raises SIGPROF; the handler reads pc and frame pointer from the
//! `ucontext`, walks the frame-pointer chain inside the stack bounds recorded at
//! start and stores the pcs in a preallocated ring (no allocation, async-signal-safe).
//! At exit the pcs are resolved through the function table and aggregated.
#[cfg(any(unix, feature = "alloc-profile"))]
use crate::fault::segment_state;
use crate::fault::{TABLES, find_func, segment_of};
use crate::global::Process;
use crate::num;
use crate::sys;
use core::sync::atomic::{AtomicUsize, Ordering};
use ms_rt_abi::Tables;
use stdalloc::collections::BTreeMap;
use stdalloc::vec::Vec;

const MAX_SAMPLES: usize = 65_536;
const MAX_FRAMES: usize = 128;
/// One sample: frame count followed by pcs, innermost first.
const SAMPLE_WORDS: usize = MAX_FRAMES + 1;

static ENABLED: AtomicUsize = AtomicUsize::new(0);
static BUFFER: Process<*mut usize> = Process::new(core::ptr::null_mut());
static COUNT: AtomicUsize = AtomicUsize::new(0);
static DROPPED: AtomicUsize = AtomicUsize::new(0);
static PATH: Process<&'static [u8]> = Process::new(b"");

// Allocation profile (`MS_PROFILE_ALLOCS=<path>`): every `ALLOC_PERIOD`th allocation of the
// runtime thread stores its stack and size. A slot is `ALLOC_WORDS` words: a sample
// (see `walk`) followed by the requested size.
const ALLOC_WORDS: usize = SAMPLE_WORDS + 1;
const DEFAULT_ALLOC_PERIOD: i64 = 128;
static ALLOC_BUFFER: Process<*mut usize> = Process::new(core::ptr::null_mut());
static ALLOC_COUNT: AtomicUsize = AtomicUsize::new(0);
static ALLOC_DROPPED: AtomicUsize = AtomicUsize::new(0);
static ALLOC_PERIOD: AtomicUsize = AtomicUsize::new(0);
static ALLOC_PATH: Process<&'static [u8]> = Process::new(b"");

#[cfg(unix)]
mod regs {
    // Offsets of the program counter and frame pointer from the register block of the signal
    // context: inside `ucontext_t` on Linux, inside the `mcontext` it points to on macOS.
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    pub const PC_OFFSET: usize = 40 + 16 * 8;
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    pub const FP_OFFSET: usize = 40 + 10 * 8;
    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    pub const PC_OFFSET: usize = 440;
    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    pub const FP_OFFSET: usize = 416;
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    pub const PC_OFFSET: usize = 16 + 16 * 8;
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    pub const FP_OFFSET: usize = 16 + 6 * 8;
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    pub const PC_OFFSET: usize = 16 + 32 * 8;
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    pub const FP_OFFSET: usize = 16 + 29 * 8;

    /// The register block of a signal context.
    ///
    /// # Safety
    /// `uctx` is the context pointer a `SA_SIGINFO` handler received.
    pub unsafe fn registers(uctx: *mut u8) -> *mut u8 {
        #[cfg(target_os = "macos")]
        // SAFETY: `uc_mcontext` is the pointer at offset 48 of `ucontext_t`.
        return unsafe { *(uctx.add(48) as *const *mut u8) };
        #[cfg(not(target_os = "macos"))]
        return uctx;
    }
}

/// Writes one sample at `base`: the frame count, then the pcs, innermost first. The pcs are
/// `pc` and the frame-pointer chain from `fp`, which lies on the running segment `seg` (the
/// sampled thread's `segment_state`).
///
/// # Safety
/// `base` has room for `SAMPLE_WORDS` words; frame reads stay inside the recorded stack bounds.
unsafe fn walk(base: *mut usize, pc: usize, mut fp: usize, mut seg: (usize, usize, usize)) {
    // SAFETY: as documented.
    unsafe {
        let mut k = 0;
        *base.add(1) = pc;
        k += 1;
        while k < MAX_FRAMES && fp != 0 && fp.is_multiple_of(8) {
            // Unknown bounds record the program counter alone.
            let Some(bounds) = segment_of(fp, seg) else {
                break;
            };
            if bounds.1 == 0 {
                break;
            }
            seg = bounds;
            let (next, ret) = (*(fp as *const usize), *((fp + 8) as *const usize));
            if ret == 0 {
                break;
            }
            *base.add(1 + k) = ret;
            k += 1;
            // Frames go up within a segment; the segment below may lie anywhere.
            if next <= fp && next >= seg.0 {
                break;
            }
            fp = next;
        }
        *base = k;
    }
}

/// Stores one sample.
fn record(pc: usize, fp: usize, seg: (usize, usize, usize)) {
    let n = COUNT.load(Ordering::Relaxed);
    if n >= MAX_SAMPLES {
        DROPPED.fetch_add(1, Ordering::Relaxed);
        return;
    }
    // SAFETY: the buffer holds MAX_SAMPLES slots.
    unsafe { walk((*BUFFER.ptr()).add(n * SAMPLE_WORDS), pc, fp, seg) };
    COUNT.store(n + 1, Ordering::Relaxed);
}

#[cfg(unix)]
extern "C" fn on_sample(_sig: i32, _info: *mut u8, uctx: *mut u8) {
    // SAFETY: the ucontext is provided by the kernel.
    let (pc, fp) = unsafe {
        let r = regs::registers(uctx);
        (
            *(r.add(regs::PC_OFFSET) as *const usize),
            *(r.add(regs::FP_OFFSET) as *const usize),
        )
    };
    // The signal runs on the sampled thread, so its own state is the sampled one.
    record(pc, fp, segment_state());
}

fn parse_hz() -> i64 {
    sys::env_var(b"MS_PROFILE_HZ\0")
        .and_then(num::parse_int_decimal)
        .filter(|hz| (1..=10_000).contains(hz))
        .unwrap_or(1000)
}

#[cfg(unix)]
unsafe fn arm_timer() {
    let act = sys::sigaction_t::new(
        on_sample as *const () as usize,
        sys::SA_SIGINFO | sys::SA_RESTART,
    );
    // SAFETY: installs the sampling handler and the profiling timer.
    unsafe {
        sys::sigaction(sys::SIGPROF, &act, core::ptr::null_mut());
        let usec = 1_000_000 / parse_hz();
        let tv = sys::timeval {
            sec: usec / 1_000_000,
            usec: usec % 1_000_000,
        };
        let it = sys::itimerval {
            interval: tv,
            value: tv,
        };
        sys::setitimer(sys::ITIMER_PROF, &it, core::ptr::null_mut());
    }
}

#[cfg(unix)]
unsafe fn disarm_timer() {
    let off = sys::itimerval {
        interval: sys::timeval { sec: 0, usec: 0 },
        value: sys::timeval { sec: 0, usec: 0 },
    };
    // SAFETY: disables the timer; sample data is then stable.
    unsafe { sys::setitimer(sys::ITIMER_PROF, &off, core::ptr::null_mut()) };
}

/// Windows has no profiling signal: a sampler thread suspends the runtime thread at the
/// sampling rate and reads its registers. The thread is attached once it exists.
#[cfg(windows)]
mod sampler {
    use super::*;
    use crate::fault::{STACK_CHAIN, STACK_HI, STACK_LO};
    use core::ffi::c_void;

    static TARGET: Process<*mut c_void> = Process::new(core::ptr::null_mut());
    static SAMPLER: Process<*mut c_void> = Process::new(core::ptr::null_mut());
    /// The runtime thread's segment cells (`STACK_LO`, `STACK_HI`, `STACK_CHAIN`), which live in
    /// that thread's storage: the sampler reads them from outside, as it reads the thread's registers.
    static CELLS: Process<[*const usize; 3]> = Process::new([core::ptr::null(); 3]);

    unsafe extern "system" fn run(_: *mut c_void) -> u32 {
        let ms = (1000 / parse_hz()).max(1) as u32;
        // SAFETY: the target handle outlives the sampler (it is joined before the handle closes).
        let target = unsafe { *TARGET.ptr() };
        while ENABLED.load(Ordering::Relaxed) != 0 {
            sys::sleep_ms(ms);
            if ENABLED.load(Ordering::Relaxed) == 0 {
                break;
            }
            // SAFETY: `target` is a sampling handle of the runtime thread.
            if let Some((pc, fp)) = unsafe { sys::sample_thread(target) } {
                // SAFETY: the cells outlive the runtime thread's sampling; a racing read at worst
                // ends the walk early.
                let seg = unsafe {
                    let [lo, hi, chain] = *CELLS.ptr();
                    (
                        lo.read_volatile(),
                        hi.read_volatile(),
                        chain.read_volatile(),
                    )
                };
                record(pc, fp, seg);
            }
        }
        0
    }

    pub unsafe fn start_sampling() {
        // SAFETY: called on the runtime thread when profiling is enabled.
        unsafe {
            let target = sys::current_thread_for_sampling();
            if target.is_null() {
                return;
            }
            *TARGET.ptr() = target;
            *CELLS.ptr() = [
                STACK_LO.ptr().cast_const(),
                STACK_HI.ptr().cast_const(),
                STACK_CHAIN.ptr().cast_const(),
            ];
            *SAMPLER.ptr() = sys::thread_spawn(0, run);
        }
    }

    pub unsafe fn stop_sampling() {
        // SAFETY: waits for the sampler to see `ENABLED == 0`, then releases both handles.
        unsafe {
            let (sampler, target) = (*SAMPLER.ptr(), *TARGET.ptr());
            if !sampler.is_null() {
                sys::thread_join(sampler);
            }
            if !target.is_null() {
                sys::close_handle(target);
            }
            *SAMPLER.ptr() = core::ptr::null_mut();
            *TARGET.ptr() = core::ptr::null_mut();
        }
    }
}

/// Called on the runtime thread before `main` runs: starts the sampler, which needs that thread.
#[cfg(windows)]
pub fn attach_runtime_thread() {
    if ENABLED.load(Ordering::Relaxed) != 0 {
        // SAFETY: runs on the runtime thread.
        unsafe { sampler::start_sampling() };
    }
}

#[cfg(windows)]
unsafe fn arm_timer() {}

#[cfg(windows)]
unsafe fn disarm_timer() {
    // SAFETY: `ENABLED` is already clear, so the sampler exits.
    unsafe { sampler::stop_sampling() };
}

/// Prepares the allocation profile when `MS_PROFILE_ALLOCS` names an output file;
/// `MS_PROFILE_ALLOC_PERIOD` (default 128) is the number of allocations per sample.
fn start_allocs() {
    let Some(path) = sys::env_var(b"MS_PROFILE_ALLOCS\0").filter(|p| !p.is_empty()) else {
        return;
    };
    let period = sys::env_var(b"MS_PROFILE_ALLOC_PERIOD\0")
        .and_then(num::parse_int_decimal)
        .filter(|n| *n >= 1)
        .unwrap_or(DEFAULT_ALLOC_PERIOD);
    // SAFETY: one-time setup before the runtime thread allocates under sampling.
    unsafe {
        let bytes = MAX_SAMPLES * ALLOC_WORDS * core::mem::size_of::<usize>();
        let p = sys::map_anon(bytes);
        if p.is_null() || !sys::commit(p, bytes) {
            return;
        }
        *ALLOC_BUFFER.ptr() = p as *mut usize;
        *ALLOC_PATH.ptr() = path;
    }
    ALLOC_PERIOD.store(period as usize, Ordering::Relaxed);
}

/// Starts sampling when `MS_PROFILE` names an output file; also writes the perf map on request.
pub fn start() {
    start_allocs();
    let Some(path) = sys::env_var(b"MS_PROFILE\0") else {
        return;
    };
    if path.is_empty() {
        return;
    }
    // SAFETY: one-time setup before sampling begins.
    unsafe {
        *PATH.ptr() = path;
        let bytes = MAX_SAMPLES * SAMPLE_WORDS * core::mem::size_of::<usize>();
        let p = sys::map_anon(bytes);
        if p.is_null() || !sys::commit(p, bytes) {
            return;
        }
        *BUFFER.ptr() = p as *mut usize;
        #[cfg(unix)]
        if sys::env_var(b"MS_PERF_MAP\0").is_some_and(|v| v == b"1") {
            write_perf_map();
        }
        ENABLED.store(1, Ordering::Relaxed);
        arm_timer();
    }
}

fn cstr(t: &Tables, off: u32) -> &'static [u8] {
    if off as usize >= t.strings_len {
        return b"?";
    }
    // SAFETY: NUL-terminated names inside the blob.
    unsafe {
        let p = t.strings.add(off as usize);
        let max = t.strings_len - off as usize;
        let mut n = 0;
        while n < max && *p.add(n) != 0 {
            n += 1;
        }
        core::slice::from_raw_parts(p, n)
    }
}

#[cfg(unix)]
fn write_perf_map() {
    // SAFETY: the table pointer is installed at start.
    let t = unsafe { *TABLES.ptr() };
    if t.is_null() {
        return;
    }
    // SAFETY: valid table.
    let t = unsafe { &*t };
    let mut out = Vec::new();
    if !t.funcs.is_null() {
        // SAFETY: `func_count` read-only entries.
        let funcs = unsafe { core::slice::from_raw_parts(t.funcs, t.func_count) };
        for f in funcs {
            let _ = std::io::Write::write_fmt(&mut out, format_args!("{:x} {:x} ", f.addr, f.size));
            out.extend_from_slice(cstr(t, f.name_off));
            out.push(b'\n');
        }
    }
    let mut path = Vec::new();
    path.extend_from_slice(b"/tmp/perf-");
    // SAFETY: `getpid` has no preconditions.
    crate::num::push_i64(&mut path, unsafe { sys::getpid() } as i64);
    path.extend_from_slice(b".map\0");
    write_file(path.as_slice(), out.as_slice());
}

fn write_file(path_nul: &[u8], data: &[u8]) {
    // SAFETY: NUL-terminated path.
    unsafe {
        let fd = sys::open(
            path_nul.as_ptr().cast(),
            sys::O_WRONLY | sys::O_CREAT | sys::O_TRUNC,
            0o644,
        );
        if fd >= 0 {
            sys::write_all(fd, data);
            sys::close(fd);
        }
    }
}

/// Folds `n` samples of `stride` words at `base` into `stack -> total weight`. `weight` reads one
/// sample's weight; names come from `t` (hex pcs without tables), outermost frame first.
///
/// # Safety
/// `base` holds `n` fully written samples of `stride` words.
unsafe fn fold(
    t: Option<&Tables>,
    base: *const usize,
    n: usize,
    stride: usize,
    weight: impl Fn(*const usize) -> u64,
) -> BTreeMap<Vec<u8>, u64> {
    let mut folded: BTreeMap<Vec<u8>, u64> = BTreeMap::new();
    for s in 0..n {
        // SAFETY: as documented.
        let (sample, frames) = unsafe {
            let p = base.add(s * stride);
            (p, core::slice::from_raw_parts(p.add(1), *p))
        };
        let mut names: Vec<Vec<u8>> = Vec::new();
        for (i, &pc) in frames.iter().enumerate() {
            let label = match t {
                Some(t) => {
                    // The top frame is an exact pc; callers are return addresses.
                    let probe = if i == 0 { pc + 1 } else { pc };
                    match find_func(t, probe) {
                        Some(f) => cstr(t, f.name_off).to_vec(),
                        None => b"[runtime]".to_vec(),
                    }
                }
                None => {
                    let mut b = Vec::new();
                    let _ = std::io::Write::write_fmt(&mut b, format_args!("0x{pc:x}"));
                    b.as_slice().to_vec()
                }
            };
            if names
                .last()
                .is_some_and(|l| l == &label && label == b"[runtime]")
            {
                continue;
            }
            names.push(label);
        }
        names.reverse();
        let mut key = Vec::new();
        for (i, nme) in names.iter().enumerate() {
            if i > 0 {
                key.push(b';');
            }
            key.extend_from_slice(nme);
        }
        if key.is_empty() {
            continue;
        }
        *folded.entry(key).or_insert(0) += weight(sample);
    }
    folded
}

/// Writes `folded` as `stack weight` lines followed by `# <trailer> <value>` comments.
fn write_folded(path: &[u8], folded: &BTreeMap<Vec<u8>, u64>, trailer: &[(&[u8], u64)]) {
    let mut out = Vec::new();
    for (stack, count) in folded {
        out.extend_from_slice(stack);
        out.push(b' ');
        crate::num::push_i64(&mut out, *count as i64);
        out.push(b'\n');
    }
    for (name, value) in trailer {
        out.extend_from_slice(b"# ");
        out.extend_from_slice(name);
        out.push(b' ');
        crate::num::push_i64(&mut out, *value as i64);
        out.push(b'\n');
    }
    // Make a NUL-terminated copy of the path.
    let mut p = Vec::new();
    p.extend_from_slice(path);
    p.push(0);
    write_file(p.as_slice(), out.as_slice());
}

/// The allocation profiler's sample for an allocation of `size` bytes on the runtime thread
/// (`alloc::sample_alloc`): stores the stack and size, and returns the allocations until the next.
#[cfg(feature = "alloc-profile")]
pub fn alloc_sample(size: usize) -> i64 {
    let period = ALLOC_PERIOD.load(Ordering::Relaxed);
    if period == 0 {
        return i64::MAX;
    }
    let n = ALLOC_COUNT.load(Ordering::Relaxed);
    if n >= MAX_SAMPLES {
        ALLOC_DROPPED.fetch_add(1, Ordering::Relaxed);
        return period as i64;
    }
    let fp = frame_pointer();
    // SAFETY: `fp` is this function's frame (the runtime keeps frame pointers): its saved caller
    // frame and return address are the stack above it. The buffer holds MAX_SAMPLES slots.
    unsafe {
        let (caller_fp, ret) = (*(fp as *const usize), *((fp + 8) as *const usize));
        let base = (*ALLOC_BUFFER.ptr()).add(n * ALLOC_WORDS);
        walk(base, ret, caller_fp, segment_state());
        *base.add(ALLOC_WORDS - 1) = size;
    }
    ALLOC_COUNT.store(n + 1, Ordering::Relaxed);
    period as i64
}

/// The frame pointer of the calling function.
#[cfg(feature = "alloc-profile")]
#[inline(always)]
fn frame_pointer() -> usize {
    let fp: usize;
    // SAFETY: reads a register.
    #[cfg(target_arch = "x86_64")]
    unsafe {
        core::arch::asm!("mov {}, rbp", out(reg) fp, options(nomem, nostack, preserves_flags));
    }
    // SAFETY: reads a register.
    #[cfg(target_arch = "aarch64")]
    unsafe {
        core::arch::asm!("mov {}, x29", out(reg) fp, options(nomem, nostack, preserves_flags));
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    {
        fp = 0;
    }
    fp
}

/// Starts allocation sampling on the runtime thread when `start` enabled it.
pub fn attach_alloc_sampling() {
    let period = ALLOC_PERIOD.load(Ordering::Relaxed);
    if period != 0 {
        crate::alloc::sample_every(period as i64);
    }
}

/// Writes the allocation profile: `<path>` weights stacks by allocation count and
/// `<path>.bytes` by bytes, both scaled by the sampling period, with the totals as comments.
fn finish_allocs(t: Option<&Tables>) {
    let period = ALLOC_PERIOD.swap(0, Ordering::Relaxed) as u64;
    if period == 0 {
        return;
    }
    let n = ALLOC_COUNT.load(Ordering::Relaxed).min(MAX_SAMPLES);
    // SAFETY: the buffer was installed at start; `n` samples were fully written.
    let base = unsafe { *ALLOC_BUFFER.ptr() };
    // SAFETY: `p` is a fully written slot of `ALLOC_WORDS` words.
    let size = |p: *const usize| unsafe { *p.add(ALLOC_WORDS - 1) } as u64;
    // SAFETY: as above.
    let (counts, bytes) = unsafe {
        (
            fold(t, base, n, ALLOC_WORDS, |_| period),
            fold(t, base, n, ALLOC_WORDS, |p| size(p) * period),
        )
    };
    let total = |m: &BTreeMap<Vec<u8>, u64>| m.values().sum::<u64>();
    let trailer: [(&[u8], u64); 3] = [
        (b"period", period),
        (b"allocs", total(&counts)),
        (b"dropped", ALLOC_DROPPED.load(Ordering::Relaxed) as u64),
    ];
    // SAFETY: path recorded at start.
    let path = unsafe { *ALLOC_PATH.ptr() };
    write_folded(path, &counts, &trailer);
    let mut bytes_path = path.to_vec();
    bytes_path.extend_from_slice(b".bytes");
    let trailer = [(&b"period"[..], period), (b"bytes", total(&bytes))];
    write_folded(&bytes_path, &bytes, &trailer);
}

/// Stops sampling and writes the folded profiles (no-op when profiling is off).
pub fn finish() {
    // SAFETY: the tables pointer, when set, outlives the process (static data).
    let t = unsafe { (*TABLES.ptr()).as_ref() };
    finish_allocs(t);
    if ENABLED.swap(0, Ordering::Relaxed) == 0 {
        return;
    }
    // SAFETY: `ENABLED` was just cleared.
    unsafe { disarm_timer() };
    let n = COUNT.load(Ordering::Relaxed).min(MAX_SAMPLES);
    // SAFETY: the buffer was installed at start and `n` samples were fully written.
    let folded = unsafe { fold(t, *BUFFER.ptr(), n, SAMPLE_WORDS, |_| 1) };
    // SAFETY: path recorded at start.
    let path = unsafe { *PATH.ptr() };
    write_folded(
        path,
        &folded,
        &[(b"dropped", DROPPED.load(Ordering::Relaxed) as u64)],
    );
}
