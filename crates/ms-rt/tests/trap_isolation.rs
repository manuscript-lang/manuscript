//! Exercise the production fork/guard path, not the unit-test panic substitute.
#![cfg(unix)]
#![allow(unsafe_code)]

use ms_rt::{fault, obj, string, trap};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

static LOCK: Mutex<()> = Mutex::new(());

struct Trace(PathBuf);

impl Trace {
    fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!("ms-trap-{}-{name}", std::process::id()));
        std::fs::write(&path, []).unwrap();
        Self(path)
    }

    fn record(&self, text: &str) {
        std::fs::OpenOptions::new()
            .append(true)
            .open(&self.0)
            .unwrap()
            .write_all(text.as_bytes())
            .unwrap();
    }

    fn read(&self) -> String {
        std::fs::read_to_string(&self.0).unwrap()
    }
}

impl Drop for Trace {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

unsafe extern "C-unwind" fn record_outer(arg: *mut u8) {
    // SAFETY: every caller retains its trace until the cleanup runs.
    unsafe { &*arg.cast::<Trace>() }.record("outer;");
}

unsafe extern "C-unwind" fn record_first(arg: *mut u8) {
    // SAFETY: every caller retains its trace until the cleanup runs.
    unsafe { &*arg.cast::<Trace>() }.record("first;");
}

unsafe extern "C-unwind" fn record_second(arg: *mut u8) {
    // SAFETY: every caller retains its trace until the cleanup runs.
    unsafe { &*arg.cast::<Trace>() }.record("second;");
}

fn capture(operation: impl FnOnce()) -> Option<String> {
    if trap::msrt_trap_begin() == 0 {
        operation();
        trap::msrt_trap_end();
    }
    let mut message = std::ptr::null_mut();
    // SAFETY: the message out pointer is writable and the trap belongs to this thread.
    let faulted = unsafe { trap::msrt_trap_wait(&mut message) };
    if faulted == 0 {
        return None;
    }
    // SAFETY: a successful wait transfers a live runtime string to the caller.
    unsafe {
        let text = String::from_utf8_lossy(string::bytes(message)).into_owned();
        obj::release(message.cast());
        Some(text)
    }
}

#[test]
fn child_fault_keeps_parent_cleanup_pending() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut trace = Trace::new("parent");
    // SAFETY: the trace stays live until this cleanup is run below.
    let handle = unsafe { fault::msrt_cleanup_push(record_outer, (&raw mut trace).cast()) };
    let message = capture(|| fault::fault(b"child fault"));
    let child_effects = trace.read();
    fault::msrt_cleanup_run(handle);
    assert_eq!(message.as_deref(), Some("child fault"));
    assert_eq!(child_effects, "", "child must not run its parent's cleanup");
    assert_eq!(trace.read(), "outer;", "parent still owns its cleanup");
}

#[test]
fn child_fault_ignores_parent_guard_and_runs_own_cleanups_lifo() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut trace = Trace::new("guard");
    // SAFETY: the trace stays live until both the guard and cleanup finish.
    let handle = unsafe { fault::msrt_cleanup_push(record_outer, (&raw mut trace).cast()) };
    unsafe extern "C-unwind" fn guarded(arg: *mut u8) {
        let message = capture(|| {
            // SAFETY: the enclosing test owns the trace throughout the child operation.
            unsafe {
                fault::msrt_cleanup_push(record_first, arg);
                fault::msrt_cleanup_push(record_second, arg);
            }
            fault::fault(b"guarded child fault");
        });
        assert_eq!(message.as_deref(), Some("guarded child fault"));
    }
    // SAFETY: serialized runtime access; the callback borrows this live trace.
    let status =
        unsafe { fault::msrt_guard_call(guarded, (&raw mut trace).cast(), std::ptr::null_mut()) };
    if status != 0 {
        // An inherited guard must never return here in the child.
        ms_rt::process::exit(99);
    }
    let child_effects = trace.read();
    fault::msrt_cleanup_run(handle);
    assert_eq!(child_effects, "second;first;");
    assert_eq!(trace.read(), "second;first;outer;");
}

#[test]
fn nested_traps_keep_their_own_cleanup_boundaries() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut trace = Trace::new("nested");
    let message = capture(|| {
        // SAFETY: the enclosing test owns the trace throughout both children.
        unsafe { fault::msrt_cleanup_push(record_first, (&raw mut trace).cast()) };
        assert_eq!(capture(|| fault::fault(b"inner")).as_deref(), Some("inner"));
        assert_eq!(trace.read(), "");
        assert_eq!(capture(|| ()), None);
        fault::fault(b"outer");
    });
    assert_eq!(message.as_deref(), Some("outer"));
    assert_eq!(trace.read(), "first;");
}

#[test]
fn trap_inside_fault_cleanup_has_a_fresh_fault_report() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut trace = Trace::new("faulting");
    unsafe extern "C-unwind" fn cleanup(arg: *mut u8) {
        assert_eq!(
            capture(|| fault::fault(b"inner cleanup")).as_deref(),
            Some("inner cleanup")
        );
        // SAFETY: the enclosing test owns the trace throughout the child operation.
        unsafe { &*arg.cast::<Trace>() }.record("caught;");
    }
    let message = capture(|| {
        // SAFETY: the trace stays live until the child's cleanup finishes.
        unsafe { fault::msrt_cleanup_push(cleanup, (&raw mut trace).cast()) };
        fault::fault(b"original fault");
    });
    assert_eq!(message.as_deref(), Some("original fault"));
    assert_eq!(trace.read(), "caught;");
}
