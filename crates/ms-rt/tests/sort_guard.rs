//! Comparator exits must leave collection owners safe under the production jump-based guard.
#![allow(unsafe_code)]

#[cfg(feature = "stats")]
use ms_rt::alloc;
use ms_rt::{fault, isolate, string, vec};
use ms_rt_abi::{KIND_INT, KIND_POD, KIND_STRING, STR_SIZE, StrVal, TypeDesc, VecVal};
use std::sync::Mutex;

static LOCK: Mutex<()> = Mutex::new(());

struct Sort {
    list: VecVal,
    out: VecVal,
    copied: bool,
    difference: bool,
    caller_drop: bool,
    descriptor: TypeDesc,
    callback: Callback,
}

struct Callback {
    calls: usize,
    exit_at: usize,
    cancel: bool,
    strings: bool,
}

unsafe extern "C-unwind" fn compare(env: *mut u8, a: *const u8, b: *const u8) -> i64 {
    // SAFETY: each sort lends this live state and two initialized descriptor-sized slots.
    unsafe {
        let state = &mut *env.cast::<Callback>();
        state.calls += 1;
        if state.calls == state.exit_at {
            if state.cancel {
                fault::msrt_cancelled();
            }
            fault::fault(b"sort comparator fault");
        }
        let order = if state.strings {
            string::bytes(a.cast::<StrVal>()).cmp(string::bytes(b.cast::<StrVal>()))
        } else {
            (*a.cast::<u64>()).cmp(&*b.cast::<u64>())
        };
        match order {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }
    }
}

unsafe extern "C-unwind" fn sort(env: *mut u8) {
    // SAFETY: state owns its live list and descriptor throughout this call.
    unsafe {
        let state = &mut *env.cast::<Sort>();
        if state.difference {
            vec::msrt_list_sorted_by_difference(
                &raw const state.list,
                &raw const state.descriptor,
                compare_difference,
                (&raw mut state.callback).cast(),
                0,
                &raw mut state.out,
            );
            return;
        }
        if state.copied {
            vec::msrt_list_sorted(
                &raw const state.list,
                &raw const state.descriptor,
                compare,
                (&raw mut state.callback).cast(),
                &raw mut state.out,
            );
            return;
        }
        vec::msrt_list_sort_in_place(
            &raw mut state.list,
            &raw const state.descriptor,
            compare,
            (&raw mut state.callback).cast(),
        );
    }
}

unsafe extern "C-unwind" fn compare_difference(env: *mut u8, a: *const u8, b: *const u8) -> i64 {
    // SAFETY: this adapter receives live Int slots and the same callback state as compare.
    unsafe {
        compare(env, a, b);
        (*a.cast::<i64>())
            .checked_sub(*b.cast::<i64>())
            .unwrap_or_else(|| fault::fault(b"sort comparator overflow"))
    }
}

unsafe extern "C-unwind" fn drop_input(env: *mut u8) {
    // SAFETY: the caller retains state through cleanup and owns the original list.
    unsafe {
        let state = &mut *env.cast::<Sort>();
        vec::drop_list(&raw mut state.list, &state.descriptor);
    }
}

unsafe extern "C-unwind" fn sort_with_caller_cleanup(env: *mut u8) {
    // SAFETY: cleanup is consumed on normal return or by the guard's exit before state dies.
    unsafe {
        let handle = fault::msrt_cleanup_push(drop_input, env);
        sort(env);
        fault::msrt_cleanup_run(handle);
    }
}

fn input(n: usize, words: usize, interleaved: bool, strings: bool) -> Sort {
    let descriptor = TypeDesc {
        size: if strings {
            STR_SIZE as u32
        } else {
            (words * 8) as u32
        },
        align: 8,
        kind: if strings { KIND_STRING } else { KIND_POD },
        reserved: 0,
        inner0: std::ptr::null(),
        inner1: std::ptr::null(),
        drop: None,
        copy: None,
        eq: None,
        hash: None,
    };
    let mut state = Sort {
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
        copied: false,
        difference: false,
        caller_drop: false,
        descriptor,
        callback: Callback {
            calls: 0,
            exit_at: usize::MAX,
            cancel: false,
            strings,
        },
    };
    for i in 0..n {
        let key = if interleaved { (i % 2) * n + i } else { n - i };
        // SAFETY: the append consumes an initialized independent slot of this descriptor.
        unsafe {
            if strings {
                let value = string::from_bytes(
                    format!("{key:03}-owned-string-beyond-inline-capacity").as_bytes(),
                );
                vec::msrt_list_push(
                    &raw mut state.list,
                    &state.descriptor,
                    (&raw const value).cast(),
                );
            } else {
                let value = [key as u64; 7];
                vec::msrt_list_push(
                    &raw mut state.list,
                    &state.descriptor,
                    value.as_ptr().cast(),
                );
            }
        }
    }
    state
}

fn values(state: &Sort, list: &VecVal) -> Vec<Vec<u8>> {
    (0..list.len)
        .map(|i| {
            // SAFETY: every list slot remains initialized with its declared descriptor.
            unsafe {
                let slot = list.ptr.add(i * state.descriptor.size as usize);
                if state.callback.strings {
                    string::bytes(slot.cast::<StrVal>()).to_vec()
                } else {
                    std::slice::from_raw_parts(slot, state.descriptor.size as usize).to_vec()
                }
            }
        })
        .collect()
}

fn run_guarded(state: &mut Sort) -> u8 {
    let mut message = string::NO_STR;
    // SAFETY: state and message outlive the production guard, including its jump on exit.
    unsafe {
        let operation = if state.caller_drop {
            sort_with_caller_cleanup
        } else {
            sort
        };
        let status =
            fault::msrt_guard_call(operation, (state as *mut Sort).cast(), &raw mut message);
        if status == 1 {
            assert!(string::bytes(&message).starts_with(b"sort comparator"));
            string::release(&message);
        }
        status
    }
}

#[test]
fn guarded_difference_sort_drops_unpublished_output_on_comparator_exit() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    isolate::set_main();
    for (exit_at, cancel) in [(1, false), (1, true), (usize::MAX, false)] {
        #[cfg(feature = "stats")]
        let before = alloc::live_blocks();
        let mut state = input(0, 1, false, false);
        state.descriptor.kind = KIND_INT;
        state.difference = true;
        state.callback.exit_at = exit_at;
        state.callback.cancel = cancel;
        for value in [i64::MAX, i64::MIN, 0] {
            // SAFETY: each append consumes an independent live Int.
            unsafe {
                vec::msrt_list_push(
                    &raw mut state.list,
                    &state.descriptor,
                    (&raw const value).cast(),
                )
            };
        }
        let original = values(&state, &state.list);
        assert_eq!(run_guarded(&mut state), if cancel { 2 } else { 1 });
        assert_eq!(values(&state, &state.list), original);
        assert!(state.out.ptr.is_null());
        assert_eq!(state.out.len, 0);
        // SAFETY: only the original input remains owned after the unpublished result is freed.
        unsafe { vec::drop_list(&raw mut state.list, &state.descriptor) };
        #[cfg(feature = "stats")]
        assert_eq!(alloc::live_blocks(), before);
    }
}

#[test]
fn guarded_sort_restores_owned_elements_before_caller_cleanup_drops_them() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    isolate::set_main();
    for cancel in [false, true] {
        for n in [3, 13, 40] {
            for exit_at in [1, 3] {
                #[cfg(feature = "stats")]
                let before = alloc::live_blocks();
                let mut state = input(n, 2, false, true);
                state.caller_drop = true;
                state.callback.exit_at = exit_at;
                state.callback.cancel = cancel;
                assert_eq!(run_guarded(&mut state), if cancel { 2 } else { 1 });
                assert!(state.list.ptr.is_null());
                assert_eq!(state.list.len, 0);
                #[cfg(feature = "stats")]
                assert_eq!(alloc::live_blocks(), before);
            }
        }
    }
}

struct CleanupWitness {
    sort: Sort,
    expected: Vec<Vec<u8>>,
}

unsafe extern "C-unwind" fn inspect_and_drop_input(env: *mut u8) {
    // SAFETY: the child retains its witness until the fault runs this explicit cleanup.
    unsafe {
        let witness = &mut *env.cast::<CleanupWitness>();
        if values(&witness.sort, &witness.sort.list) != witness.expected {
            eprintln!("explicit cleanup observed corrupted sort owners");
            std::process::exit(99);
        }
        vec::drop_list(&raw mut witness.sort.list, &witness.sort.descriptor);
        #[cfg(feature = "stats")]
        assert_eq!(alloc::live_blocks(), 0);
        use std::io::Write;
        let mut stdout = std::io::stdout();
        stdout.write_all(b"sort-owner-cleanup-ok\n").unwrap();
        stdout.flush().unwrap();
    }
}

#[test]
fn unguarded_sort_restores_owners_before_explicit_cleanup() {
    const CASE: &str = "MS_RT_TEST_UNGUARDED_SORT";
    if let Ok(case) = std::env::var(CASE) {
        isolate::set_main();
        let (count, exit) = case.split_once(':').unwrap();
        let mut state = input(count.parse().unwrap(), 2, false, true);
        state.callback.exit_at = 3;
        state.callback.cancel = exit == "cancel";
        if state.callback.cancel {
            fault::PENDING_SIGNAL.store(2, std::sync::atomic::Ordering::Relaxed);
        }
        let mut witness = CleanupWitness {
            expected: values(&state, &state.list),
            sort: state,
        };
        // SAFETY: the witness outlives both the sort and its process-exit cleanup.
        unsafe {
            assert_eq!(
                (*fault::msrt_isolate_hdr())
                    .guarded
                    .load(std::sync::atomic::Ordering::Relaxed),
                0
            );
            fault::msrt_cleanup_push(inspect_and_drop_input, (&raw mut witness).cast());
            sort((&raw mut witness.sort).cast());
        }
        panic!("expected unguarded comparator exit");
    }
    for count in [3, 13, 40] {
        for (exit, code) in [("fault", 67), ("cancel", 130)] {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "unguarded_sort_restores_owners_before_explicit_cleanup",
                    "--nocapture",
                ])
                .env(CASE, format!("{count}:{exit}"))
                .output()
                .unwrap();
            assert_eq!(
                output.status.code(),
                Some(code),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(String::from_utf8_lossy(&output.stdout).contains("sort-owner-cleanup-ok"));
        }
    }
}

#[test]
fn guarded_sort_faults_and_cancellation_preserve_owners_and_release_scratch() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    isolate::set_main();
    // Both specialized words and the >48-byte generic merge, plus independently owned strings.
    for (words, strings) in [(1, false), (7, false), (2, true)] {
        for copied in [false, true] {
            for n in 0..=40 {
                for interleaved in [false, true] {
                    let mut success = input(n, words, interleaved, strings);
                    success.copied = copied;
                    let original = values(&success, &success.list);
                    let mut expected = original.clone();
                    expected.sort();
                    assert_eq!(run_guarded(&mut success), 0);
                    assert_eq!(
                        values(&success, if copied { &success.out } else { &success.list }),
                        expected
                    );
                    if copied {
                        assert_eq!(values(&success, &success.list), original);
                    }
                    let calls = success.callback.calls;
                    // SAFETY: successful sort preserves one owner for every element.
                    unsafe {
                        vec::drop_list(&raw mut success.list, &success.descriptor);
                        vec::drop_list(&raw mut success.out, &success.descriptor);
                    };
                    for cancel in [false, true] {
                        for exit_at in 1..=calls {
                            #[cfg(feature = "stats")]
                            let before = alloc::live_blocks();
                            let mut state = input(n, words, interleaved, strings);
                            state.copied = copied;
                            state.callback.exit_at = exit_at;
                            state.callback.cancel = cancel;
                            assert_eq!(run_guarded(&mut state), if cancel { 2 } else { 1 });
                            assert_eq!(
                                values(&state, &state.list),
                                original,
                                "words={words} strings={strings} copied={copied} n={n} interleaved={interleaved} exit_at={exit_at} cancel={cancel}"
                            );
                            assert!(state.out.ptr.is_null());
                            assert_eq!(state.out.len, 0);
                            // SAFETY: rollback restored the original independent owners before this drop.
                            unsafe { vec::drop_list(&raw mut state.list, &state.descriptor) };
                            #[cfg(feature = "stats")]
                            assert_eq!(alloc::live_blocks(), before, "sort scratch leaked");
                        }
                    }
                }
            }
        }
    }
}
