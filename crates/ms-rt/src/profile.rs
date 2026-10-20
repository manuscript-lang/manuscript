//! Sampling profiler: `MS_PROFILE=<path>` writes folded stacks at exit.
//!
//! `ITIMER_PROF` raises SIGPROF; the handler reads pc and frame pointer from the
//! `ucontext`, walks the frame-pointer chain inside the stack bounds recorded at
//! start and stores the pcs in a preallocated ring (no allocation, async-signal-safe).
//! At exit the pcs are resolved through the function table and aggregated.
use crate::fault::{STACK_HI, STACK_LO, TABLES, find_func};
use crate::global::Global;
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
static BUFFER: Global<*mut usize> = Global::new(core::ptr::null_mut());
static COUNT: AtomicUsize = AtomicUsize::new(0);
static DROPPED: AtomicUsize = AtomicUsize::new(0);
static PATH: Global<&'static [u8]> = Global::new(b"");

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

/// Stores one sample: the program counter and the frame-pointer chain from `fp`.
fn record(pc: usize, mut fp: usize) {
    let n = COUNT.load(Ordering::Relaxed);
    if n >= MAX_SAMPLES {
        DROPPED.fetch_add(1, Ordering::Relaxed);
        return;
    }
    // SAFETY: the buffer holds MAX_SAMPLES slots; frame reads stay inside the recorded stack
    // bounds.
    unsafe {
        let base = (*BUFFER.ptr()).add(n * SAMPLE_WORDS);
        let (lo, hi) = (*STACK_LO.ptr(), *STACK_HI.ptr());
        let mut k = 0;
        *base.add(1) = pc;
        k += 1;
        while k < MAX_FRAMES && fp != 0 && fp.is_multiple_of(8) && fp >= lo && fp + 16 <= hi {
            let (next, ret) = (*(fp as *const usize), *((fp + 8) as *const usize));
            if ret == 0 {
                break;
            }
            *base.add(1 + k) = ret;
            k += 1;
            if next <= fp {
                break;
            }
            fp = next;
        }
        *base = k;
    }
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
    record(pc, fp);
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
    use core::ffi::c_void;

    static TARGET: Global<*mut c_void> = Global::new(core::ptr::null_mut());
    static SAMPLER: Global<*mut c_void> = Global::new(core::ptr::null_mut());

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
                record(pc, fp);
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

/// Starts sampling when `MS_PROFILE` names an output file; also writes the perf map on request.
pub fn start() {
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

/// Stops sampling and writes the folded profile (no-op when profiling is off).
pub fn finish() {
    if ENABLED.swap(0, Ordering::Relaxed) == 0 {
        return;
    }
    // SAFETY: `ENABLED` was just cleared.
    unsafe { disarm_timer() };
    let n = COUNT.load(Ordering::Relaxed).min(MAX_SAMPLES);
    // SAFETY: table and buffer were installed at start.
    let (t, base) = unsafe { (*TABLES.ptr(), *BUFFER.ptr()) };
    // SAFETY: the tables pointer, when set, outlives the process (static data).
    let t = unsafe { t.as_ref() };
    let mut folded: BTreeMap<Vec<u8>, u64> = BTreeMap::new();
    for s in 0..n {
        // SAFETY: sample `s < COUNT` was fully written before COUNT advanced.
        let (len, frames) = unsafe {
            let p = base.add(s * SAMPLE_WORDS);
            (*p, core::slice::from_raw_parts(p.add(1), *p))
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
        let _ = len;
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
        *folded.entry(key).or_insert(0) += 1;
    }
    let mut out = Vec::new();
    for (stack, count) in &folded {
        out.extend_from_slice(stack);
        out.push(b' ');
        crate::num::push_i64(&mut out, *count as i64);
        out.push(b'\n');
    }
    out.extend_from_slice(b"# dropped ");
    crate::num::push_i64(&mut out, DROPPED.load(Ordering::Relaxed) as i64);
    out.push(b'\n');
    // SAFETY: path recorded at start; make a NUL-terminated copy.
    let path = unsafe { *PATH.ptr() };
    let mut p = Vec::new();
    p.extend_from_slice(path);
    p.push(0);
    write_file(p.as_slice(), out.as_slice());
}
