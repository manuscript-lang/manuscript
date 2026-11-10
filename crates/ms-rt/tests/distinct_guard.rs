//! Equality and hash callback exits must release `distinct`'s unpublished result and set.
#![allow(unsafe_code)]

#[cfg(feature = "stats")]
use ms_rt::alloc;
use ms_rt::{fault, isolate, string, vec};
use ms_rt_abi::{KIND_CUSTOM, STR_SIZE, StrVal, TypeDesc, VecVal};
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

static LOCK: Mutex<()> = Mutex::new(());
static CALLS: AtomicUsize = AtomicUsize::new(0);
static EXIT_AT: AtomicUsize = AtomicUsize::new(usize::MAX);
static CANCEL: AtomicUsize = AtomicUsize::new(0);

fn tick() {
    if CALLS.fetch_add(1, Ordering::SeqCst) + 1 == EXIT_AT.load(Ordering::SeqCst) {
        if CANCEL.load(Ordering::SeqCst) != 0 {
            fault::msrt_cancelled();
        }
        fault::fault(b"distinct callback fault");
    }
}

unsafe extern "C" fn eq(a: *const u8, b: *const u8) -> u8 {
    tick();
    // SAFETY: both slots hold live strings.
    unsafe { (string::bytes(a.cast::<StrVal>()) == string::bytes(b.cast::<StrVal>())) as u8 }
}

unsafe extern "C" fn hash(_: *const u8) -> i64 {
    tick();
    7
}

unsafe extern "C" fn drop_slot(s: *mut u8) {
    // SAFETY: the slot holds a live string.
    unsafe { string::release(&*s.cast::<StrVal>()) }
}

unsafe extern "C" fn copy_slot(src: *const u8, dst: *mut u8) {
    // SAFETY: `src` is live and `dst` is uninitialized string storage.
    unsafe { *dst.cast::<StrVal>() = string::cloned(&*src.cast::<StrVal>()) }
}

struct Run {
    list: VecVal,
    out: VecVal,
    descriptor: TypeDesc,
}

unsafe extern "C-unwind" fn distinct(env: *mut u8) {
    // SAFETY: the state outlives the guard.
    unsafe {
        let r = &mut *env.cast::<Run>();
        vec::msrt_list_distinct(&raw const r.list, &raw const r.descriptor, &raw mut r.out);
    }
}

fn run(n: usize, hashed: bool, exit_at: usize, cancel: bool) -> u8 {
    CALLS.store(0, Ordering::SeqCst);
    EXIT_AT.store(exit_at, Ordering::SeqCst);
    CANCEL.store(cancel as usize, Ordering::SeqCst);
    let mut r = Run {
        list: VecVal {
            ptr: std::ptr::null_mut(),
            len: 0,
            cap: 0,
        },
        out: VecVal {
            ptr: std::ptr::null_mut(),
            len: 0,
            cap: 0,
        },
        descriptor: TypeDesc {
            size: STR_SIZE as u32,
            align: 8,
            kind: KIND_CUSTOM,
            reserved: 0,
            inner0: std::ptr::null(),
            inner1: std::ptr::null(),
            drop: Some(drop_slot),
            copy: Some(copy_slot),
            eq: Some(eq),
            hash: if hashed { Some(hash) } else { None },
        },
    };
    for i in 0..n {
        let v =
            string::from_bytes(format!("{i:03}-owned-string-beyond-inline-capacity").as_bytes());
        // SAFETY: the push moves an initialized slot.
        unsafe { vec::msrt_list_push(&raw mut r.list, &r.descriptor, (&raw const v).cast()) };
    }
    let mut message = string::NO_STR;
    // SAFETY: state and message outlive the guard.
    let status = unsafe { fault::msrt_guard_call(distinct, (&raw mut r).cast(), &raw mut message) };
    if status == 1 {
        // SAFETY: the guard stored a message string.
        unsafe { string::release(&message) };
    }
    assert_eq!(r.list.len, n);
    if status == 0 {
        assert_eq!(r.out.len, n);
        // SAFETY: the published result is owned here.
        unsafe { vec::drop_list(&raw mut r.out, &r.descriptor) };
    } else {
        assert!(r.out.ptr.is_null());
    }
    // SAFETY: the input stays owned by the caller.
    unsafe { vec::drop_list(&raw mut r.list, &r.descriptor) };
    status
}

#[test]
fn distinct_guard_releases_unpublished_result_and_set() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    isolate::set_main();
    // The first guarded call allocates the task's cleanup stack once.
    run(1, false, usize::MAX, false);
    for (n, hashed) in [(5, false), (5, true), (20, true)] {
        // Every callback position: the lookup hash, the insertion hash (after the key was copied)
        // and the equality calls.
        for exit_at in 1..=6 {
            for cancel in [false, true] {
                #[cfg(feature = "stats")]
                let before = alloc::live_blocks();
                let status = run(n, hashed, exit_at, cancel);
                assert_eq!(status, if cancel { 2 } else { 1 });
                #[cfg(feature = "stats")]
                assert_eq!(
                    alloc::live_blocks(),
                    before,
                    "n={n} hashed={hashed} exit_at={exit_at}"
                );
            }
        }
        #[cfg(feature = "stats")]
        let before = alloc::live_blocks();
        assert_eq!(run(n, hashed, usize::MAX, false), 0);
        #[cfg(feature = "stats")]
        assert_eq!(alloc::live_blocks(), before, "n={n} hashed={hashed}");
    }
}
