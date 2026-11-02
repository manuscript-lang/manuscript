//! Resource contracts of the pure codecs, counted on the calling test thread only.
#![allow(unsafe_code)]

use ms_rt::ffi::Fail;
use ms_std_core::encoding::{
    ascii85_decode, base32_decode, base32_encode, base64_decode_unpadded, base64_encode_unpadded,
};
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

#[derive(Clone, Copy, Debug, Default)]
struct Counts {
    allocations: usize,
    reallocations: usize,
}

thread_local! {
    static TRACKING: Cell<Option<Counts>> = const { Cell::new(None) };
}

struct CountingAllocator;

fn record(reallocation: bool) {
    let _ = TRACKING.try_with(|slot| {
        if let Some(mut counts) = slot.get() {
            if reallocation {
                counts.reallocations = counts.reallocations.saturating_add(1);
            } else {
                counts.allocations = counts.allocations.saturating_add(1);
            }
            slot.set(Some(counts));
        }
    });
}

// SAFETY: every operation delegates the caller's pointer, layout and size unchanged to System.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        record(false);
        // SAFETY: GlobalAlloc's caller supplies a valid allocation layout.
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        record(false);
        // SAFETY: GlobalAlloc's caller supplies a valid allocation layout.
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        record(true);
        // SAFETY: GlobalAlloc's caller supplies its live allocation and valid new size.
        unsafe { System.realloc(ptr, layout, new_size) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        // SAFETY: GlobalAlloc's caller supplies the live allocation's original layout.
        unsafe { System.dealloc(ptr, layout) }
    }
}

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

struct ResetTracking;

impl Drop for ResetTracking {
    fn drop(&mut self) {
        let _ = TRACKING.try_with(|slot| slot.set(None));
    }
}

fn counted<T>(work: impl FnOnce() -> T) -> (T, Counts) {
    TRACKING.with(|slot| assert!(slot.replace(Some(Counts::default())).is_none()));
    let _reset = ResetTracking;
    let value = work();
    let counts = TRACKING.with(|slot| slot.replace(None).unwrap());
    (value, counts)
}

#[test]
fn unpadded_base64_reserves_output_without_reallocation() {
    for length in [0, 1, 3, 4, 6, 7, 9, 19, 21, 37, 4096, 8193] {
        let data: Vec<u8> = (0..length).map(|i| (i * 73 + 11) as u8).collect();
        for url_safe in [false, true] {
            let (encoded, counts) = counted(|| base64_encode_unpadded(&data, url_safe));
            assert_eq!(
                base64_decode_unpadded(&encoded, url_safe, None),
                Ok(data.clone())
            );
            assert_eq!(
                counts.allocations,
                usize::from(length != 0),
                "{length}: {counts:?}"
            );
            assert_eq!(counts.reallocations, 0, "{length}: {counts:?}");
        }
        for hex in [false, true] {
            for padded in [false, true] {
                let (encoded, counts) = counted(|| base32_encode(&data, hex, padded));
                assert_eq!(base32_decode(&encoded, hex, padded, None), Ok(data.clone()));
                assert_eq!(counts.reallocations, 0, "Base32 {length}: {counts:?}");
            }
        }
    }
}

#[test]
fn bounded_ascii85_checks_the_complete_output_before_allocating() {
    for (text, limit) in [("zz", 7), ("!!!!!!!!!!", 7), ("z z", 4), ("!!!!!z", 4)] {
        let (result, counts) = counted(|| ascii85_decode(text, Some(limit)));
        assert_eq!(result, Err(Fail::LimitExceeded));
        assert_eq!(counts.allocations, 0, "{text:?}: {counts:?}");
        assert_eq!(counts.reallocations, 0, "{text:?}: {counts:?}");
    }
    for (text, limit) in [("", 0), (" \t\r\n", 0), ("zz", 8), ("!!!!!z", 8), ("!!", 1)] {
        let (result, counts) = counted(|| ascii85_decode(text, Some(limit)));
        let bytes = result.unwrap();
        assert!(bytes.len() <= limit as usize);
        assert_eq!(counts.allocations, usize::from(!bytes.is_empty()));
        assert_eq!(counts.reallocations, 0);
    }
    for text in ["!", "z!", "!!!!!v", "uuuuu"] {
        let (result, counts) = counted(|| ascii85_decode(text, Some(100)));
        assert_eq!(result, Err(Fail::InvalidData));
        assert_eq!(counts.allocations, 0, "{text:?}: {counts:?}");
    }
    let (negative, counts) = counted(|| ascii85_decode("zz", Some(-1)));
    assert_eq!(negative, Err(Fail::InvalidInput));
    assert_eq!(counts.allocations, 0);
    for (text, limit, expected) in [
        ("zzv", 4, Fail::LimitExceeded),
        ("zv", 4, Fail::InvalidData),
        ("uuuuu", 0, Fail::InvalidData),
    ] {
        let (result, counts) = counted(|| ascii85_decode(text, Some(limit)));
        assert_eq!(result, Err(expected));
        assert_eq!(counts.allocations, 0);
    }
}

#[test]
fn base32_internal_padding_precedes_output_limits_without_changing_other_errors() {
    for hex in [false, true] {
        for (padded, text) in [
            (true, "A=AAAAAA"),
            (true, "AA======AA======"),
            (false, "A=AA"),
        ] {
            assert_eq!(
                base32_decode(text, hex, padded, Some(0)),
                Err(Fail::InvalidData)
            );
            assert_eq!(
                base32_decode(text, hex, padded, Some(-1)),
                Err(Fail::InvalidInput)
            );
            assert_eq!(
                base32_decode(text, hex, padded, None),
                Err(Fail::InvalidData)
            );
        }
        for padded in [false, true] {
            assert_eq!(
                base32_decode("!!!!!!!!", hex, padded, Some(0)),
                Err(Fail::LimitExceeded)
            );
        }
    }
    for url_safe in [false, true] {
        assert_eq!(
            base64_decode_unpadded("A=AA", url_safe, Some(0)),
            Err(Fail::LimitExceeded)
        );
    }
}
