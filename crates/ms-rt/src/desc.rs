//! Type descriptors: drop, copy, equality and hash of values stored in slots.
use ms_rt_abi::*;

// Defined in C (runtime/core); declared here for the Rust code that still calls them.
unsafe extern "C-unwind" {
    pub safe static msrt_desc_int: TypeDesc;
    pub safe static msrt_desc_float: TypeDesc;
    pub safe static msrt_desc_float32: TypeDesc;
    pub safe static msrt_desc_bool: TypeDesc;
    pub safe static msrt_desc_string: TypeDesc;
    pub safe static msrt_desc_bytes: TypeDesc;
    pub fn msrt_slot_drop(d: *const TypeDesc, slot: *mut u8);
    pub fn msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8);
    pub fn msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8;
    pub fn msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64;
    pub safe fn msrt_hash_combine(a: i64, b: i64) -> i64;
}
