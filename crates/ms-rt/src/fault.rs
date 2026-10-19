//! Faults, the cleanup stack, call depth, cancellation and process exit.
use crate::buf::{ByteBuf, RawVec};
use crate::global::Global;
#[allow(unused_imports)]
use crate::sys;
use core::fmt::{self, Write};
use ms_rt_abi::{FuncEntry, LineEntry, MAX_FAULT_FRAMES, Tables};

/// Current depth of recursive calls (generated code updates it inline).
#[unsafe(no_mangle)]
pub static mut msrt_call_depth: i64 = 0;
/// Non-zero (the signal number) once a stop was requested and not shielded.
#[unsafe(no_mangle)]
pub static mut msrt_cancel_flag: u8 = 0;

pub static TABLES: Global<*const Tables> = Global::new(core::ptr::null());
/// Lowest and highest valid stack addresses for frame walking (0 = unknown).
pub static STACK_LO: Global<usize> = Global::new(0);
pub static STACK_HI: Global<usize> = Global::new(0);

type CleanupFn = unsafe extern "C-unwind" fn(*mut u8);
static CLEANUPS: Global<RawVec<(usize, usize)>> = Global::new(RawVec::new());
pub(crate) static SHIELD: Global<u32> = Global::new(0);
pub static PENDING_SIGNAL: core::sync::atomic::AtomicU8 = core::sync::atomic::AtomicU8::new(0);
static FAULTING: Global<bool> = Global::new(false);
static SECONDARY: Global<RawVec<(usize, usize)>> = Global::new(RawVec::new());

/// Fault reported while no frames or cleanup are meaningful (allocator exhaustion).
#[cold]
pub fn fatal(msg: &[u8]) -> ! {
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(
            std::string::String::from_utf8_lossy(msg).into_owned(),
        ));
    }
    #[cfg(not(test))]
    {
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, msg);
        sys::write_all(sys::STDERR, b"\n");
        // SAFETY: terminating the process.
        unsafe { sys::_exit(ms_rt_abi::EXIT_FAULT) }
    }
}

#[inline(always)]
fn frame_pointer() -> usize {
    let fp: usize;
    // SAFETY: reads a register, no memory access.
    unsafe {
        #[cfg(target_arch = "x86_64")]
        core::arch::asm!("mov {}, rbp", out(reg) fp, options(nomem, nostack, preserves_flags));
        #[cfg(target_arch = "aarch64")]
        core::arch::asm!("mov {}, x29", out(reg) fp, options(nomem, nostack, preserves_flags));
        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        {
            fp = 0;
        }
    }
    fp
}

/// Walks a frame-pointer chain starting at `fp`, calling `f(return_address)`
/// until it returns false or the chain ends.
///
/// # Safety
/// `fp` must be null or point into a live frame-pointer chain of this thread.
pub unsafe fn walk_frames(mut fp: usize, mut f: impl FnMut(usize) -> bool) {
    // SAFETY: reading the global stack bounds, set once at start.
    let (lo, hi) = unsafe { (*STACK_LO.ptr(), *STACK_HI.ptr()) };
    let mut steps = 0usize;
    while fp != 0 && fp.is_multiple_of(8) && steps < 1_000_000 {
        if hi != 0 && (fp < lo || fp + 16 > hi) {
            break;
        }
        // SAFETY: `fp` is inside the stack bounds (or bounds are unknown and the
        // caller promised a valid chain).
        let (next, ret) = unsafe { (*(fp as *const usize), *((fp + 8) as *const usize)) };
        if ret == 0 || !f(ret) {
            break;
        }
        if next <= fp {
            break;
        }
        fp = next;
        steps += 1;
    }
}

fn cstr(t: &Tables, off: u32) -> &'static [u8] {
    if off == u32::MAX || off as usize >= t.strings_len {
        return b"?";
    }
    // SAFETY: the compiler emits NUL-terminated strings inside the blob.
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

/// Finds the function containing `pc` (a return address).
pub fn find_func(t: &Tables, pc: usize) -> Option<&'static FuncEntry> {
    if t.funcs.is_null() || t.func_count == 0 {
        return None;
    }
    // SAFETY: the table is `func_count` sorted entries of read-only data.
    let funcs = unsafe { core::slice::from_raw_parts(t.funcs, t.func_count) };
    let probe = pc.wrapping_sub(1);
    let idx = funcs.partition_point(|e| e.addr <= probe);
    if idx == 0 {
        return None;
    }
    let e = &funcs[idx - 1];
    if probe < e.addr + e.size as usize {
        Some(e)
    } else {
        None
    }
}

/// Source line of a return address inside `func`.
pub fn find_line(t: &Tables, func: &FuncEntry, pc: usize) -> (u32, u32) {
    if !t.lines.is_null() && t.line_count > 0 {
        // SAFETY: sorted `line_count` read-only entries.
        let lines = unsafe { core::slice::from_raw_parts(t.lines, t.line_count) };
        // `pc` is a return address; the call instruction lies in the range ending just before it.
        let probe = pc.wrapping_sub(1);
        let idx = lines.partition_point(|e: &LineEntry| e.pc <= probe);
        if idx > 0 {
            let e = &lines[idx - 1];
            if e.pc >= func.addr {
                let file = if e.file_off == u32::MAX {
                    func.file_off
                } else {
                    e.file_off
                };
                return (e.line, file);
            }
        }
    }
    (func.line, func.file_off)
}

/// Appends `file:line in name` lines for the source frames found from `fp`.
fn describe_frames(out: &mut ByteBuf, fp: usize) {
    // SAFETY: tables pointer is set once at start.
    let t = unsafe { *TABLES.ptr() };
    if t.is_null() {
        return;
    }
    // SAFETY: non-null table installed by `msrt_start`.
    let t = unsafe { &*t };
    let mut shown = 0;
    let mut truncated = false;
    // SAFETY: `fp` comes from `frame_pointer()` of the faulting thread.
    unsafe {
        walk_frames(fp, |ret| {
            let Some(func) = find_func(t, ret) else {
                return true;
            };
            if shown == MAX_FAULT_FRAMES {
                truncated = true;
                return false;
            }
            let (line, file) = find_line(t, func, ret);
            out.extend(b"\n  at ");
            out.extend(cstr(t, file));
            out.push(b':');
            out.push_i64(line as i64);
            out.extend(b" in ");
            out.extend(cstr(t, func.name_off));
            shown += 1;
            true
        });
    }
    if truncated {
        out.extend(b"\n  ... outer frames omitted");
    }
}

/// Runs `f(arg)` with cancellation shielded.
fn run_shielded(f: CleanupFn, arg: *mut u8) {
    // SAFETY: single threaded access to the shield counter; the action was
    // registered by generated code with a valid function pointer.
    unsafe {
        *SHIELD.ptr() += 1;
        msrt_cancel_flag = 0;
        f(arg);
        *SHIELD.ptr() -= 1;
        if *SHIELD.ptr() == 0 {
            msrt_cancel_flag = PENDING_SIGNAL.load(core::sync::atomic::Ordering::Relaxed);
        }
    }
}

/// Pops and runs the innermost cleanup action; false when none remain.
fn run_one_cleanup() -> bool {
    // SAFETY: single threaded access to the cleanup stack.
    let action = unsafe { (*CLEANUPS.ptr()).pop() };
    match action {
        Some((f, arg)) => {
            // SAFETY: `f` was stored from a valid `CleanupFn` whose provenance `as usize` exposed.
            let f: CleanupFn = unsafe {
                core::mem::transmute::<*const (), CleanupFn>(core::ptr::with_exposed_provenance(f))
            };
            run_shielded(f, core::ptr::with_exposed_provenance_mut(arg));
            true
        }
        None => false,
    }
}

/// The full fault path: trace, cleanups LIFO, report, exit 70.
#[cold]
#[inline(never)]
pub fn fault(msg: &[u8]) -> ! {
    // SAFETY: single threaded access to the fault state.
    unsafe {
        if *FAULTING.ptr() {
            // A fault inside a cleanup action: record it and keep unwinding from here.
            let mut copy = ByteBuf::with_capacity(msg.len());
            copy.extend(msg);
            let (p, l, _) = copy.into_raw();
            (*SECONDARY.ptr()).push((p as usize, l));
            while run_one_cleanup() {}
            finish_report(None)
        }
        *FAULTING.ptr() = true;
    }
    let mut report = ByteBuf::with_capacity(msg.len() + 256);
    report.extend(msg);
    describe_frames(&mut report, frame_pointer());
    // SAFETY: single threaded; a fault inside a cleanup action finishes this report.
    unsafe { *PRIMARY.ptr() = Some(report) };
    while run_one_cleanup() {}
    finish_report(None)
}

static PRIMARY: Global<Option<ByteBuf>> = Global::new(None);

fn finish_report(primary: Option<ByteBuf>) -> ! {
    // SAFETY: single threaded access to the report state.
    let mut report = unsafe {
        if let Some(p) = primary {
            *PRIMARY.ptr() = Some(p);
        }
        (*PRIMARY.ptr()).take().unwrap_or_default()
    };
    // SAFETY: secondary messages were stored from `ByteBuf::into_raw`.
    unsafe {
        let sec = &mut *SECONDARY.ptr();
        for i in 0..sec.len() {
            let (p, l) = sec.get(i);
            report.extend(b"\ncleanup fault: ");
            report.extend(core::slice::from_raw_parts(p as *const u8, l));
            crate::alloc::free(p as *mut u8);
        }
        sec.clear();
        *FAULTING.ptr() = false;
    }
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(
            std::string::String::from_utf8_lossy(report.as_slice()).into_owned(),
        ));
    }
    #[cfg(not(test))]
    {
        report.push(b'\n');
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, report.as_slice());
        crate::process::exit(ms_rt_abi::EXIT_FAULT)
    }
}

/// Faults with a formatted message.
#[cold]
pub fn fault_fmt(args: fmt::Arguments) -> ! {
    let mut b = ByteBuf::new();
    let _ = b.write_fmt(args);
    fault(b.as_slice())
}

/// Convenience: `fault!("fmt {}", x)`.
#[macro_export]
macro_rules! fault {
    ($($arg:tt)*) => { $crate::fault::fault_fmt(format_args!($($arg)*)) };
}

// ---- exported entry points ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fault(msg: *const u8, len: usize) -> ! {
    // SAFETY: caller passes a readable range.
    fault(unsafe { core::slice::from_raw_parts(msg, len) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fault_string(s: *mut ms_rt_abi::StrObj) -> ! {
    // SAFETY: caller passes a live string.
    fault(unsafe { crate::string::bytes(s) })
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_depth() -> ! {
    // SAFETY: single threaded counter reset so cleanups can run calls.
    unsafe { msrt_call_depth = 0 };
    fault_fmt(format_args!(
        "call depth limit exceeded ({} nested calls)",
        ms_rt_abi::MAX_CALL_DEPTH
    ))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_index_fault(index: i64, length: i64) -> ! {
    fault_fmt(format_args!(
        "index {index} out of range for length {length}; pass a default: get(index:, default: ...)"
    ))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_unwrap_none() -> ! {
    fault(
        b"called Optional.get() on none; check is_some first, or pass a default: get(default: ...)",
    )
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_result_get() -> ! {
    fault(b"called Result.get() on error; check is_ok first, or pass a default: get(default: ...)")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_result_err() -> ! {
    fault(b"called Result.err() on ok; check is_error first")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_int_overflow() -> ! {
    fault(b"Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_div_zero() -> ! {
    fault(b"Int./: division by zero; right must be nonzero, found 0")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_rem_zero() -> ! {
    fault(b"Int.%: remainder by zero; right must be nonzero, found 0")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_div_overflow(a: i64, b: i64) -> ! {
    fault_fmt(format_args!(
        "Int./: overflow; found left {a} and right {b}; result must be between {} and {}",
        i64::MIN,
        i64::MAX
    ))
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let s = &mut *CLEANUPS.ptr();
        s.push((f as usize, arg as usize));
        s.len()
    }
}

/// Runs the action behind `handle` (and newer pending ones first).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cleanup_run(handle: usize) {
    // SAFETY: single threaded access to the cleanup stack.
    while unsafe { (*CLEANUPS.ptr()).len() } >= handle && handle > 0 {
        run_one_cleanup();
    }
}

/// Unwinds on a stop request: runs cleanups and exits 130/143.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancelled() -> ! {
    let sig = PENDING_SIGNAL.load(core::sync::atomic::Ordering::Relaxed);
    while run_one_cleanup() {}
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(std::format!(
            "cancelled {sig}"
        )));
    }
    #[cfg(not(test))]
    crate::process::exit(if sig == sys::SIGINT as u8 {
        ms_rt_abi::EXIT_INTERRUPT
    } else {
        ms_rt_abi::EXIT_TERMINATE
    })
}

#[cfg(test)]
pub fn reset_for_tests() {
    // SAFETY: tests hold the global lock.
    unsafe {
        (*CLEANUPS.ptr()).clear();
        *FAULTING.ptr() = false;
        (*SECONDARY.ptr()).clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{fault_of, lock};

    static LOG: Global<[u8; 8]> = Global::new([0; 8]);
    static LOG_N: Global<usize> = Global::new(0);

    unsafe extern "C-unwind" fn log_action(arg: *mut u8) {
        // SAFETY: tests hold the lock; LOG has room for 8 entries.
        unsafe {
            let n = *LOG_N.ptr();
            (*LOG.ptr())[n] = arg as usize as u8;
            *LOG_N.ptr() = n + 1;
        }
    }

    unsafe extern "C-unwind" fn faulting_action(_arg: *mut u8) {
        fault(b"close failed");
    }

    #[test]
    #[cfg_attr(miri, ignore = "faults use inline asm, which Miri cannot run")]
    fn cleanups_run_lifo_on_fault_with_secondary() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: test-only access.
        unsafe { *LOG_N.ptr() = 0 };
        // SAFETY: valid function pointers.
        unsafe {
            msrt_cleanup_push(log_action, core::ptr::dangling_mut::<u8>());
            msrt_cleanup_push(faulting_action, core::ptr::null_mut());
            msrt_cleanup_push(log_action, 3 as *mut u8);
        }
        let text = fault_of(|| fault(b"boom")).unwrap();
        assert_eq!(text, "boom\ncleanup fault: close failed");
        // SAFETY: test-only access.
        unsafe {
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[3, 1]);
        }
    }

    #[test]
    fn cleanup_run_pops_to_handle() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: test-only access and valid function pointers.
        unsafe {
            *LOG_N.ptr() = 0;
            let h1 = msrt_cleanup_push(log_action, core::ptr::dangling_mut::<u8>());
            let _h2 = msrt_cleanup_push(log_action, 2 as *mut u8);
            msrt_cleanup_run(h1);
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[2, 1]);
            msrt_cleanup_run(h1);
            assert_eq!(*LOG_N.ptr(), 2);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "faults use inline asm, which Miri cannot run")]
    fn frames_resolve_through_tables() {
        let _g = lock();
        reset_for_tests();
        // Fake frame chain: three frames with return addresses 0x1010, 0x2010, 0x9999.
        let mut chain: [[usize; 2]; 3] = [[0, 0x1010], [0, 0x2010], [0, 0x9999]];
        chain[0][0] = &chain[1] as *const _ as usize;
        chain[1][0] = &chain[2] as *const _ as usize;
        let strings = b"\0outer\0inner\0a.ms\0";
        let funcs = [
            FuncEntry {
                addr: 0x1000,
                size: 0x100,
                name_off: 7,
                file_off: 13,
                line: 3,
            },
            FuncEntry {
                addr: 0x2000,
                size: 0x100,
                name_off: 1,
                file_off: 13,
                line: 9,
            },
        ];
        let lines = [LineEntry {
            pc: 0x1008,
            line: 4,
            file_off: u32::MAX,
        }];
        let t = Tables {
            abi_version: 1,
            reserved: 0,
            funcs: funcs.as_ptr(),
            func_count: 2,
            lines: lines.as_ptr(),
            line_count: 1,
            strings: strings.as_ptr(),
            strings_len: strings.len(),
        };
        // SAFETY: test-only access to globals; `t` outlives the use.
        unsafe { *TABLES.ptr() = &t };
        let mut out = ByteBuf::new();
        describe_frames(&mut out, &chain[0] as *const _ as usize);
        // SAFETY: restore.
        unsafe { *TABLES.ptr() = core::ptr::null() };
        assert_eq!(
            core::str::from_utf8(out.as_slice()).unwrap(),
            "\n  at a.ms:4 in inner\n  at a.ms:9 in outer"
        );
    }

    #[test]
    #[cfg_attr(miri, ignore = "faults use inline asm, which Miri cannot run")]
    fn named_faults_use_go_messages() {
        let _g = lock();
        reset_for_tests();
        assert_eq!(
            fault_of(|| msrt_index_fault(7, 3)).unwrap(),
            "index 7 out of range for length 3; pass a default: get(index:, default: ...)"
        );
        assert_eq!(
            fault_of(|| msrt_fault_depth()).unwrap(),
            "call depth limit exceeded (200000 nested calls)"
        );
    }
}
