//! Comparator exits must leave collection owners safe under the production jump-based guard.
#![allow(unsafe_code)]

#[cfg(feature = "stats")]
use ms_rt::alloc;
use ms_rt::{fault, isolate, string, vec};
use ms_rt_abi::{KIND_POD, KIND_STRING, STR_SIZE, StrVal, TypeDesc, VecVal};
use std::sync::Mutex;

static LOCK: Mutex<()> = Mutex::new(());

struct Sort {
    list: VecVal,
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
        vec::msrt_list_sort_in_place(
            &raw mut state.list,
            &raw const state.descriptor,
            compare,
            (&raw mut state.callback).cast(),
        );
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

fn values(state: &Sort) -> Vec<Vec<u8>> {
    (0..state.list.len)
        .map(|i| {
            // SAFETY: every list slot remains initialized with its declared descriptor.
            unsafe {
                let slot = state.list.ptr.add(i * state.descriptor.size as usize);
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
        let status = fault::msrt_guard_call(sort, (state as *mut Sort).cast(), &raw mut message);
        if status == 1 {
            assert!(string::bytes(&message).starts_with(b"sort comparator fault"));
            string::release(&message);
        }
        status
    }
}

#[test]
fn guarded_sort_faults_and_cancellation_preserve_owners_and_release_scratch() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    isolate::set_main();
    // Both specialized words and the >48-byte generic merge, plus independently owned strings.
    for (words, strings) in [(1, false), (7, false), (2, true)] {
        for n in 0..=40 {
            for interleaved in [false, true] {
                let mut success = input(n, words, interleaved, strings);
                let original = values(&success);
                let mut expected = original.clone();
                expected.sort();
                assert_eq!(run_guarded(&mut success), 0);
                assert_eq!(values(&success), expected);
                let calls = success.callback.calls;
                // SAFETY: successful sort preserves one owner for every element.
                unsafe { vec::drop_list(&raw mut success.list, &success.descriptor) };
                for cancel in [false, true] {
                    for exit_at in 1..=calls {
                        #[cfg(feature = "stats")]
                        let before = alloc::live_blocks();
                        let mut state = input(n, words, interleaved, strings);
                        state.callback.exit_at = exit_at;
                        state.callback.cancel = cancel;
                        assert_eq!(run_guarded(&mut state), if cancel { 2 } else { 1 });
                        assert_eq!(
                            values(&state),
                            original,
                            "words={words} strings={strings} n={n} interleaved={interleaved} exit_at={exit_at} cancel={cancel}"
                        );
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
