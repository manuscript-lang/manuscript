//! Safe native signatures: the [`native!`](crate::native) macro generates the `extern "C"` shim
//! from a safe Rust signature, so native bodies hold no `unsafe` and the pointer conversions live
//! here, once.
//!
//! Parameter types implement [`FromAbi`], results [`IntoAbi`], and error types [`Status`]. A
//! fallible native (`-> Result<T, E>`) returns the status byte and writes `T` through a trailing
//! out-pointer; a record result (`-> out T`) is written through a trailing out-pointer and the
//! shim returns nothing. This is the same layout the hand-written shims used.
use super::{
    Fail, StrVal, TypeDesc, VecVal, bytes_ref, new_string, new_string_bytes, read_string_list,
    str_ref, write_bytes,
};
use core::marker::PhantomData;
use core::ops::{Deref, DerefMut};
use ms_rt_abi::{Closure, MapVal, OptStr};
use std::boxed::Box;
use std::string::String;
use std::vec::Vec;

use crate::desc::{msrt_desc_int, msrt_desc_string};
use crate::map::{msrt_map_add, msrt_map_new};
use crate::obj::{msrt_alloc, msrt_free, msrt_release, msrt_retain};
use crate::start::{msrt_argv, msrt_start_nanos};
use crate::vec::{
    msrt_bytes_copy, msrt_bytes_drop, msrt_list_copy, msrt_list_drop, msrt_list_new, msrt_list_push,
};

/// The C representation of a Manuscript value type: a scalar or a pointer to a runtime value.
/// It does not depend on the borrow lifetime of the Rust type.
pub trait AbiType {
    type Raw;
}

/// A value read from its C representation.
///
/// # Safety
/// `from_raw` is called only by [`native!`](crate::native)-generated shims, whose callers
/// (generated code) pass live values of the declared Manuscript type that outlive the call.
pub unsafe trait FromAbi<'a>: AbiType {
    /// # Safety
    /// `raw` is a live value of the Manuscript type this impl reads.
    unsafe fn from_raw(raw: Self::Raw) -> Self;
}

/// A value written in its C representation.
pub trait IntoAbi {
    /// The C representation; pointers are owned by the caller (+1).
    type Raw;
    fn into_raw(self) -> Self::Raw;
}

/// An error case reported as the status byte of a fallible native.
pub trait Status {
    fn status(self) -> u8;
}

impl Status for Fail {
    fn status(self) -> u8 {
        Fail::status(self)
    }
}

macro_rules! scalar {
    ($($t:ty),*) => {$(
        impl AbiType for $t {
            type Raw = $t;
        }
        // SAFETY: a scalar is passed by value; nothing is dereferenced.
        unsafe impl FromAbi<'_> for $t {
            unsafe fn from_raw(raw: $t) -> $t { raw }
        }
        impl IntoAbi for $t {
            type Raw = $t;
            fn into_raw(self) -> $t { self }
        }
    )*};
}
scalar!(i64, f64, u8, u32, u64, i32, usize);

impl AbiType for bool {
    type Raw = u8;
}
// SAFETY: `Bool` is a byte, 0 or 1.
unsafe impl FromAbi<'_> for bool {
    unsafe fn from_raw(raw: u8) -> bool {
        raw != 0
    }
}
impl IntoAbi for bool {
    type Raw = u8;
    fn into_raw(self) -> u8 {
        u8::from(self)
    }
}

impl AbiType for &str {
    type Raw = *const StrVal;
}
// SAFETY: `String` arguments are live `StrVal`s that outlive the call.
unsafe impl<'a> FromAbi<'a> for &'a str {
    unsafe fn from_raw(raw: *const StrVal) -> &'a str {
        // SAFETY: caller contract.
        unsafe { str_ref(raw) }
    }
}
impl IntoAbi for &str {
    type Raw = StrVal;
    fn into_raw(self) -> StrVal {
        new_string(self)
    }
}
impl IntoAbi for String {
    type Raw = StrVal;
    fn into_raw(self) -> StrVal {
        new_string(&self)
    }
}

impl AbiType for &[u8] {
    type Raw = *const VecVal;
}
// SAFETY: `Bytes` arguments are live `VecVal`s that outlive the call.
unsafe impl<'a> FromAbi<'a> for &'a [u8] {
    unsafe fn from_raw(raw: *const VecVal) -> &'a [u8] {
        // SAFETY: caller contract.
        unsafe { bytes_ref(raw) }
    }
}

impl AbiType for Vec<&str> {
    type Raw = *const VecVal;
}
impl IntoAbi for Vec<u8> {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        // A large buffer is a system block, which the runtime frees like its own large blocks,
        // so it changes hands without a copy. Small ones live in arenas that Rust code may not use.
        #[cfg(all(unix, not(any(test, feature = "stats"))))]
        if self.capacity() > crate::alloc::MAX_SMALL {
            let mut v = core::mem::ManuallyDrop::new(self);
            return VecVal {
                ptr: v.as_mut_ptr(),
                len: v.len(),
                cap: v.capacity(),
            };
        }
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_bytes` initializes `v`.
        unsafe {
            crate::ffi::write_bytes(v.as_mut_ptr(), &self);
            v.assume_init()
        }
    }
}

// SAFETY: `List[String]` arguments are live and outlive the call.
unsafe impl<'a> FromAbi<'a> for Vec<&'a str> {
    unsafe fn from_raw(raw: *const VecVal) -> Vec<&'a str> {
        // SAFETY: caller contract.
        unsafe { read_string_list(raw) }
    }
}

/// A record of `N` strings (all fields `String`), laid out as `N` consecutive string values.
impl<const N: usize> AbiType for [&str; N] {
    type Raw = *const [StrVal; N];
}
// SAFETY: record arguments are live records of `N` live strings that outlive the call.
unsafe impl<'a, const N: usize> FromAbi<'a> for [&'a str; N] {
    unsafe fn from_raw(raw: *const [StrVal; N]) -> [&'a str; N] {
        // SAFETY: caller contract; each field is a live string.
        unsafe { core::array::from_fn(|i| str_ref(&(*raw)[i])) }
    }
}
impl<const N: usize> IntoAbi for [String; N] {
    type Raw = [StrVal; N];
    fn into_raw(self) -> [StrVal; N] {
        self.map(|s| new_string(&s))
    }
}

/// An owned runtime string stored inside a record (`String` field), for [`abi_record!`].
/// Dropping it does not free the string: the record's owner does that.
#[repr(transparent)]
pub struct Str(StrVal);

impl Str {
    pub fn new(s: &str) -> Str {
        Str(new_string(s))
    }

    /// A string made from host bytes the caller trusts to be text.
    pub fn from_bytes(b: &[u8]) -> Str {
        Str(new_string_bytes(b))
    }

    pub fn as_ptr(&self) -> *const StrVal {
        &raw const self.0
    }

    pub fn as_str(&self) -> &str {
        // SAFETY: a `Str` is only created by `new` or by the runtime inside a live record.
        unsafe { str_ref(&raw const self.0) }
    }
}

/// An owned `List[String]` stored inside a record, for [`abi_record!`].
#[repr(transparent)]
pub struct StringList(VecVal);

impl StringList {
    pub fn new<S: AsRef<str>>(items: impl IntoIterator<Item = S>) -> StringList {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_string_list` initializes `v`.
        unsafe {
            crate::ffi::write_string_list(v.as_mut_ptr(), items);
            StringList(v.assume_init())
        }
    }

    pub fn to_vec(&self) -> Vec<&str> {
        // SAFETY: a `StringList` is only created by `new` or by the runtime inside a live record.
        unsafe { read_string_list(&raw const self.0) }
    }
}

impl IntoAbi for StringList {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        self.0
    }
}

/// The program's whole native argument vector, including `argv[0]`.
pub fn argv() -> StringList {
    let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
    // SAFETY: `msrt_argv` initializes `v` with a fresh `List[String]`.
    unsafe {
        msrt_argv(v.as_mut_ptr());
        StringList(v.assume_init())
    }
}

/// Monotonic nanoseconds at which the runtime started; 0 when it did not record a start.
pub fn start_nanos() -> i64 {
    msrt_start_nanos()
}

/// A string result held as bytes, for host text that is checked (or trusted) to be UTF-8 by the
/// native rather than by the type.
pub struct Text(pub Vec<u8>);

impl IntoAbi for Text {
    type Raw = StrVal;
    fn into_raw(self) -> StrVal {
        new_string_bytes(&self.0)
    }
}

/// A `List[List[String]]` result built in one buffer, so a parser allocates per table rather than
/// per cell. Cell `i` is `data[ends[i - 1]..ends[i]]`; row `r` owns the cells after the previous
/// row's end up to `rows[r]`.
#[derive(Default)]
pub struct StringTable {
    data: String,
    ends: Vec<usize>,
    rows: Vec<usize>,
}

impl StringTable {
    /// Appends text to the cell being built.
    pub fn push_str(&mut self, text: &str) {
        self.data.push_str(text);
    }

    /// Closes the cell being built.
    pub fn end_cell(&mut self) {
        self.ends.push(self.data.len());
    }

    /// Closes the row of cells closed since the previous row.
    pub fn end_row(&mut self) {
        self.rows.push(self.ends.len());
    }

    /// Cells closed so far.
    pub fn cells(&self) -> usize {
        self.ends.len()
    }

    pub fn row_count(&self) -> usize {
        self.rows.len()
    }

    /// The rows as lists of cell text.
    pub fn rows(&self) -> impl Iterator<Item = impl Iterator<Item = &str>> {
        let mut cell = 0;
        self.rows.iter().map(move |&end| {
            let first = cell;
            cell = end;
            (first..end).map(move |i| {
                let from = if i == 0 { 0 } else { self.ends[i - 1] };
                &self.data[from..self.ends[i]]
            })
        })
    }

    pub fn into_rows(self) -> Vec<Vec<String>> {
        self.rows().map(|r| r.map(String::from).collect()).collect()
    }
}

impl IntoAbi for StringTable {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_string_matrix` initializes `v`.
        unsafe {
            crate::ffi::write_string_matrix(v.as_mut_ptr(), self.rows());
            v.assume_init()
        }
    }
}

/// A `Map[String, String]` result.
pub struct StrMap(pub Vec<(Vec<u8>, Vec<u8>)>);
/// A `Map[String, Int]` result.
pub struct IntMap(pub Vec<(Vec<u8>, i64)>);

impl IntoAbi for StrMap {
    type Raw = MapVal;
    fn into_raw(self) -> MapVal {
        build_map(self.0.iter().map(|(k, v)| (k, MapItem::Str(v))), false)
    }
}
impl IntoAbi for IntMap {
    type Raw = MapVal;
    fn into_raw(self) -> MapVal {
        build_map(self.0.iter().map(|(k, v)| (k, MapItem::Int(*v))), true)
    }
}

enum MapItem<'a> {
    Str(&'a [u8]),
    Int(i64),
}

fn build_map<'a>(pairs: impl Iterator<Item = (&'a Vec<u8>, MapItem<'a>)>, ints: bool) -> MapVal {
    let mut out = core::mem::MaybeUninit::<MapVal>::uninit();
    // SAFETY: `msrt_map_new` initializes `out`; each slot passed to `msrt_map_add` holds one
    // owned element that the map takes.
    unsafe {
        msrt_map_new(out.as_mut_ptr());
        let vd: *const TypeDesc = if ints {
            &raw const msrt_desc_int
        } else {
            &raw const msrt_desc_string
        };
        for (k, v) in pairs {
            let mut key = new_string_bytes(k);
            let kd = &raw const msrt_desc_string;
            match v {
                MapItem::Str(b) => {
                    let mut val = new_string_bytes(b);
                    msrt_map_add(
                        out.as_mut_ptr(),
                        kd,
                        vd,
                        (&raw mut key).cast(),
                        (&raw mut val).cast(),
                    );
                }
                MapItem::Int(mut i) => {
                    msrt_map_add(
                        out.as_mut_ptr(),
                        kd,
                        vd,
                        (&raw mut key).cast(),
                        (&raw mut i).cast(),
                    );
                }
            }
        }
        out.assume_init()
    }
}

/// A `List[String]` result held as bytes, like [`Text`].
pub struct TextList(pub Vec<Vec<u8>>);

impl IntoAbi for TextList {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `msrt_list_new` initializes `out`; each pushed string moves into the list.
        unsafe {
            msrt_list_new(out.as_mut_ptr());
            for item in &self.0 {
                let s = new_string_bytes(item);
                msrt_list_push(
                    out.as_mut_ptr(),
                    &raw const msrt_desc_string,
                    (&raw const s).cast(),
                );
            }
            out.assume_init()
        }
    }
}

/// A `List[Int]` result.
pub struct IntList(pub Vec<i64>);

impl IntoAbi for IntList {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `msrt_list_new` initializes `out`; integers are pushed by value.
        unsafe {
            msrt_list_new(out.as_mut_ptr());
            for item in &self.0 {
                msrt_list_push(
                    out.as_mut_ptr(),
                    &raw const msrt_desc_int,
                    (item as *const i64).cast(),
                );
            }
            out.assume_init()
        }
    }
}

/// A `List[Bytes]` result.
pub struct BytesList(pub Vec<Vec<u8>>);

impl IntoAbi for BytesList {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `msrt_list_new` and `write_bytes` initialize their outputs; each pushed bytes
        // value moves into the list.
        unsafe {
            msrt_list_new(out.as_mut_ptr());
            for item in &self.0 {
                let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
                write_bytes(v.as_mut_ptr(), item);
                msrt_list_push(
                    out.as_mut_ptr(),
                    crate::ffi::desc_bytes(),
                    v.as_ptr().cast(),
                );
            }
            out.assume_init()
        }
    }
}

/// A `List[Int]` argument.
impl AbiType for &[i64] {
    type Raw = *const VecVal;
}
// SAFETY: `List[Int]` arguments are live lists that outlive the call.
unsafe impl<'a> FromAbi<'a> for &'a [i64] {
    unsafe fn from_raw(raw: *const VecVal) -> &'a [i64] {
        // SAFETY: caller contract; integers are stored inline, and an empty list may carry null.
        unsafe {
            let v = &*raw;
            if v.len == 0 {
                &[]
            } else {
                core::slice::from_raw_parts(v.ptr.cast::<i64>(), v.len)
            }
        }
    }
}

/// A `List[Bytes]` argument.
impl AbiType for Vec<&[u8]> {
    type Raw = *const VecVal;
}
// SAFETY: `List[Bytes]` arguments are live lists that outlive the call.
unsafe impl<'a> FromAbi<'a> for Vec<&'a [u8]> {
    unsafe fn from_raw(raw: *const VecVal) -> Vec<&'a [u8]> {
        // SAFETY: caller contract; `VecVal`s are stored inline, and an empty list may carry null.
        unsafe {
            let v = &*raw;
            if v.len == 0 {
                return Vec::new();
            }
            (0..v.len)
                .map(|i| bytes_ref(v.ptr.cast::<VecVal>().add(i)))
                .collect()
        }
    }
}

/// One reference to a runtime object held by Rust (a child's pipes, say), released on drop. The
/// object may also be handed to Manuscript with [`ObjBox::share`].
pub struct ObjBox<T: AbiHandle>(*mut ObjCell<T>);

impl<T: AbiHandle> ObjBox<T> {
    pub fn new(value: T) -> ObjBox<T> {
        ObjBox(Object(value).into_raw())
    }

    pub fn get_mut(&mut self) -> &mut T {
        // SAFETY: `self` holds a reference, so the object is live; Manuscript code runs on one
        // thread and no other borrow is active during a native call.
        unsafe { &mut (*self.0).value }
    }

    /// Whether this box holds the only reference to the object.
    pub fn is_unique(&self) -> bool {
        // SAFETY: `self` holds a reference, so the object is live.
        unsafe { (*self.0).header.rc == 1 }
    }

    /// Another reference to the object, for returning to Manuscript.
    pub fn share(&self) -> ObjShare<T> {
        ObjShare(self.0)
    }
}

impl<T: AbiHandle> Drop for ObjBox<T> {
    fn drop(&mut self) {
        // SAFETY: releases the one reference this box owns.
        unsafe { msrt_release(self.0.cast()) }
    }
}

/// An existing runtime object handed back to the caller as another reference (the same object,
/// retained), as when one handle serves two interfaces.
pub struct ObjShare<T: AbiHandle>(*mut ObjCell<T>);

impl<T: AbiHandle> AbiType for ObjShare<T> {
    type Raw = *mut ObjCell<T>;
}
// SAFETY: an object argument is a live runtime object that outlives the call.
unsafe impl<T: AbiHandle> FromAbi<'_> for ObjShare<T> {
    unsafe fn from_raw(raw: *mut ObjCell<T>) -> ObjShare<T> {
        ObjShare(raw)
    }
}
impl<T: AbiHandle> IntoAbi for ObjShare<T> {
    type Raw = *mut ObjCell<T>;
    fn into_raw(self) -> *mut ObjCell<T> {
        // SAFETY: `self.0` is a live object; the caller receives its own reference.
        unsafe { msrt_retain(self.0.cast()) };
        self.0
    }
}

/// A runtime object returned to Manuscript: a new one, or another reference to one that Rust
/// keeps, as when a native hands out a cached handle.
pub enum Handed<T: AbiHandle> {
    New(Object<T>),
    Shared(ObjShare<T>),
}

impl<T: AbiHandle> AbiType for Handed<T> {
    type Raw = *mut ObjCell<T>;
}
impl<T: AbiHandle> IntoAbi for Handed<T> {
    type Raw = *mut ObjCell<T>;
    fn into_raw(self) -> *mut ObjCell<T> {
        match self {
            Handed::New(o) => o.into_raw(),
            Handed::Shared(s) => s.into_raw(),
        }
    }
}

/// Compiled closure code takes a `String` as its two leaves `(ptr, tagged)`, not a pointer.
type PairCode = unsafe extern "C-unwind" fn(*mut Closure, *mut u8, usize, *mut u8, usize) -> u8;
type EntryCode =
    unsafe extern "C-unwind" fn(*mut Closure, *mut u8, usize, *mut u8, usize, u8, u8) -> u8;

/// Calls `code` with temporary strings made from `bytes`, released after the call.
fn with_strings<R>(bytes: [&[u8]; 2], call: impl FnOnce(&StrVal, &StrVal) -> R) -> R {
    let (a, b) = (new_string_bytes(bytes[0]), new_string_bytes(bytes[1]));
    let r = call(&a, &b);
    // SAFETY: the callee only borrowed the strings; this releases the one reference made above.
    unsafe {
        crate::ffi::str_release(&a);
        crate::ffi::str_release(&b);
    }
    r
}

/// A nullable compiled closure over two strings, answering a bool (`copy`'s filter).
pub struct PairFilter(*mut Closure, PairCode);

impl PairFilter {
    pub fn call(&self, a: &[u8], b: &[u8]) -> bool {
        // SAFETY: the compiler built the closure with this signature (`FromAbi`).
        with_strings(
            [a, b],
            |a, b| unsafe { (self.1)(self.0, a.ptr_word, a.tagged, b.ptr_word, b.tagged) } != 0,
        )
    }
}

/// A nullable compiled closure over `(path, name, directory, symlink)` (`glob`'s exclusion).
pub struct EntryFilter(*mut Closure, EntryCode);

impl EntryFilter {
    pub fn call(&self, path: &[u8], name: &[u8], directory: bool, symlink: bool) -> bool {
        // SAFETY: the compiler built the closure with this signature (`FromAbi`).
        with_strings(
            [path, name],
            |p, n| unsafe {
                (self.1)(
                    self.0,
                    p.ptr_word,
                    p.tagged,
                    n.ptr_word,
                    n.tagged,
                    u8::from(directory),
                    u8::from(symlink),
                )
            } != 0,
        )
    }
}

impl AbiType for Option<PairFilter> {
    type Raw = *mut Closure;
}
// SAFETY: the compiler passes a closure whose code has this signature, or null.
unsafe impl FromAbi<'_> for Option<PairFilter> {
    unsafe fn from_raw(raw: *mut Closure) -> Option<PairFilter> {
        // SAFETY: caller contract.
        (!raw.is_null())
            .then(|| unsafe { PairFilter(raw, core::mem::transmute_copy(&(*raw).code)) })
    }
}
impl AbiType for Option<EntryFilter> {
    type Raw = *mut Closure;
}
// SAFETY: the compiler passes a closure whose code has this signature, or null.
unsafe impl FromAbi<'_> for Option<EntryFilter> {
    unsafe fn from_raw(raw: *mut Closure) -> Option<EntryFilter> {
        // SAFETY: caller contract.
        (!raw.is_null())
            .then(|| unsafe { EntryFilter(raw, core::mem::transmute_copy(&(*raw).code)) })
    }
}

/// A `static` for state only the runtime thread touches. Manuscript code runs on one thread, so
/// interior-mutable statics (`Global<Cell<_>>`, `Global<RefCell<_>>`) need no lock.
pub struct Global<T>(T);

impl<T> Global<T> {
    pub const fn new(value: T) -> Global<T> {
        Global(value)
    }

    /// The value. A worker cannot reach it: it is state of the main isolate.
    pub fn get(&self) -> &T {
        if crate::isolate::is_worker() {
            crate::fault::fault(
                b"this part of the standard library is only available on the main thread, not in a worker",
            );
        }
        &self.0
    }
}

// SAFETY: only the main isolate reaches a `Global` (workers fault in `get`).
unsafe impl<T> Sync for Global<T> {}

/// A bare `STATUS_*` byte as an error.
pub struct StatusCode(pub u8);

impl Status for StatusCode {
    fn status(self) -> u8 {
        self.0
    }
}

/// An owned `Bytes` value stored inside a record, for [`abi_record!`].
#[repr(transparent)]
pub struct Bytes(VecVal);

impl Bytes {
    pub fn new(b: &[u8]) -> Bytes {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_bytes` initializes `v`.
        unsafe {
            write_bytes(v.as_mut_ptr(), b);
            Bytes(v.assume_init())
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        // SAFETY: a `Bytes` is only created by `new` or by the runtime inside a live record.
        unsafe { bytes_ref(&raw const self.0) }
    }
}

/// A type that may be a field of an [`abi_record!`]. `release` and `duplicate` are the
/// drop and copy of the slot inside a runtime list or record.
pub trait AbiSlot: Sized {
    /// Releases what the slot owns.
    ///
    /// # Safety
    /// The slot is live and not used afterwards.
    unsafe fn release(&mut self);
    /// A deep copy: strings retained, lists copied.
    ///
    /// # Safety
    /// The slot is live.
    unsafe fn duplicate(&self) -> Self;
}

macro_rules! plain_slot {
    ($($t:ty),*) => {$(
        impl AbiSlot for $t {
            unsafe fn release(&mut self) {}
            unsafe fn duplicate(&self) -> $t { *self }
        }
    )*};
}
plain_slot!(i64, f64, u8, u32, u64, i32, OptInt);

/// `Int?` stored inline in a record: a presence byte, then the value.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct OptInt {
    present: u8,
    value: i64,
}

impl OptInt {
    pub fn new(v: Option<i64>) -> OptInt {
        OptInt {
            present: u8::from(v.is_some()),
            value: v.unwrap_or(0),
        }
    }

    pub fn get(&self) -> Option<i64> {
        (self.present != 0).then_some(self.value)
    }
}

impl AbiSlot for Str {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract; a `Str` owns one reference.
        unsafe { crate::ffi::str_release(&self.0) }
    }
    unsafe fn duplicate(&self) -> Str {
        // SAFETY: caller contract.
        Str(unsafe { crate::ffi::str_clone(&self.0) })
    }
}

impl AbiSlot for Bytes {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract.
        unsafe { msrt_bytes_drop(&raw mut self.0) }
    }
    unsafe fn duplicate(&self) -> Bytes {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: caller contract; `msrt_bytes_copy` initializes `v`.
        unsafe {
            msrt_bytes_copy(&raw const self.0, v.as_mut_ptr());
            Bytes(v.assume_init())
        }
    }
}

impl AbiSlot for StringList {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract.
        unsafe { msrt_list_drop(&raw mut self.0, &raw const msrt_desc_string) }
    }
    unsafe fn duplicate(&self) -> StringList {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: caller contract; `msrt_list_copy` initializes `v`.
        unsafe {
            msrt_list_copy(
                &raw const self.0,
                &raw const msrt_desc_string,
                v.as_mut_ptr(),
            );
            StringList(v.assume_init())
        }
    }
}

/// An owned `List[R]` of records, stored inside a record or returned from a native.
#[repr(transparent)]
pub struct RecList<R: AbiRecord>(VecVal, PhantomData<R>);

impl<R: AbiRecord> RecList<R> {
    pub fn new(items: impl IntoIterator<Item = R>) -> RecList<R> {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `msrt_list_new` initializes `v`; each pushed record moves into the list.
        unsafe {
            msrt_list_new(v.as_mut_ptr());
            for item in items {
                msrt_list_push(v.as_mut_ptr(), R::desc(), (&raw const item).cast());
                core::mem::forget(item);
            }
            RecList(v.assume_init(), PhantomData)
        }
    }

    pub fn as_slice(&self) -> &[R] {
        if self.0.len == 0 {
            return &[];
        }
        // SAFETY: a non-empty list holds `len` records inline at `ptr`.
        unsafe { core::slice::from_raw_parts(self.0.ptr as *const R, self.0.len) }
    }
}

impl<R: AbiRecord> AbiSlot for RecList<R> {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract.
        unsafe { msrt_list_drop(&raw mut self.0, R::desc()) }
    }
    unsafe fn duplicate(&self) -> RecList<R> {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: caller contract; `msrt_list_copy` initializes `v`.
        unsafe {
            msrt_list_copy(&raw const self.0, R::desc(), v.as_mut_ptr());
            RecList(v.assume_init(), PhantomData)
        }
    }
}

impl<R: AbiRecord> AbiType for &RecList<R> {
    type Raw = *const RecList<R>;
}
// SAFETY: list arguments are live lists that outlive the call.
unsafe impl<'a, R: AbiRecord> FromAbi<'a> for &'a RecList<R> {
    unsafe fn from_raw(raw: *const RecList<R>) -> &'a RecList<R> {
        // SAFETY: caller contract.
        unsafe { &*raw }
    }
}
impl<R: AbiRecord> IntoAbi for RecList<R> {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        self.0
    }
}

impl IntoAbi for () {
    type Raw = ();
    fn into_raw(self) {}
}

/// A runtime string passes through unchanged (+1 owned by the caller).
impl IntoAbi for StrVal {
    type Raw = StrVal;
    fn into_raw(self) -> StrVal {
        self
    }
}

impl AbiType for Vec<Vec<&str>> {
    type Raw = *const VecVal;
}
// SAFETY: `List[List[String]]` arguments are live and outlive the call.
unsafe impl<'a> FromAbi<'a> for Vec<Vec<&'a str>> {
    unsafe fn from_raw(raw: *const VecVal) -> Vec<Vec<&'a str>> {
        // SAFETY: caller contract.
        unsafe { crate::ffi::read_string_matrix(raw) }
    }
}
impl IntoAbi for Vec<Vec<String>> {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_string_matrix` initializes `v`.
        unsafe {
            crate::ffi::write_string_matrix(
                v.as_mut_ptr(),
                self.iter().map(|r| r.iter().map(String::as_str)),
            );
            v.assume_init()
        }
    }
}
impl IntoAbi for Vec<String> {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_string_list` initializes `v`.
        unsafe {
            crate::ffi::write_string_list(v.as_mut_ptr(), &self);
            v.assume_init()
        }
    }
}

/// The nullable `err: *mut StrVal` slot where a fallible native stores a `Failed` message.
pub struct ErrOut(*mut StrVal);

impl ErrOut {
    /// Stores `msg` as a fresh string, unless the caller passed no slot.
    pub fn set(&self, msg: &str) {
        if !self.0.is_null() {
            // SAFETY: a non-null `ErrOut` is a writable slot (`from_raw` contract).
            unsafe { self.0.write(new_string(msg)) }
        }
    }
}
impl AbiType for ErrOut {
    type Raw = *mut StrVal;
}
// SAFETY: the caller passes null or writable memory for one string.
unsafe impl FromAbi<'_> for ErrOut {
    unsafe fn from_raw(raw: *mut StrVal) -> ErrOut {
        ErrOut(raw)
    }
}

/// A `List[Bytes]` stored inline in a record.
#[repr(C)]
pub struct BytesVec(VecVal);

impl BytesVec {
    pub fn new(items: &[Vec<u8>]) -> BytesVec {
        BytesVec(BytesList(items.to_vec()).into_raw())
    }
}

impl AbiSlot for BytesVec {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract.
        unsafe { msrt_list_drop(&raw mut self.0, crate::ffi::desc_bytes()) }
    }
    unsafe fn duplicate(&self) -> BytesVec {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: caller contract; `msrt_list_copy` initializes `v`.
        unsafe {
            msrt_list_copy(&raw const self.0, crate::ffi::desc_bytes(), v.as_mut_ptr());
            BytesVec(v.assume_init())
        }
    }
}

/// A compiled function value passed to a native that keeps or calls it, as the raw closure object.
/// Retaining it and reading its code word is left to the (small, `unsafe`) module that owns the
/// calling convention of that closure.
#[derive(Clone, Copy)]
pub struct Handler(*mut ms_rt_abi::Obj);

impl Handler {
    pub fn as_ptr(&self) -> *mut ms_rt_abi::Obj {
        self.0
    }
}
impl AbiType for Handler {
    type Raw = *mut ms_rt_abi::Obj;
}
// SAFETY: a closure argument is a live closure object that outlives the call.
unsafe impl FromAbi<'_> for Handler {
    unsafe fn from_raw(raw: *mut ms_rt_abi::Obj) -> Handler {
        Handler(raw)
    }
}

/// A runtime object stored inline in a record (one reference), for [`abi_record!`].
#[repr(transparent)]
pub struct ObjSlot<T: AbiHandle>(*mut ObjCell<T>);

impl<T: AbiHandle> ObjSlot<T> {
    pub fn new(value: T) -> ObjSlot<T> {
        ObjSlot(Object(value).into_raw())
    }
}

impl<T: AbiHandle> AbiSlot for ObjSlot<T> {
    unsafe fn release(&mut self) {
        // SAFETY: caller contract; the slot owns one reference.
        unsafe { msrt_release(self.0.cast()) }
    }
    unsafe fn duplicate(&self) -> ObjSlot<T> {
        // SAFETY: caller contract.
        unsafe { msrt_retain(self.0.cast()) };
        ObjSlot(self.0)
    }
}

type ReadCode =
    unsafe extern "C-unwind" fn(*mut Closure, u8, i64, *mut VecVal, *mut u8, *mut StrVal) -> u8;

/// A compiled `ReadStream` closure, read with the `Connection.read` convention of `ABI.md`. It
/// borrows the closure for the duration of the native call that received it.
pub struct ReadSource(*mut Closure, ReadCode);

impl AbiType for ReadSource {
    type Raw = *mut Closure;
}
// SAFETY: a closure argument is a live closure whose code has the `ReadStream` signature.
unsafe impl FromAbi<'_> for ReadSource {
    unsafe fn from_raw(raw: *mut Closure) -> ReadSource {
        // SAFETY: the code word follows the 16-byte header (`Closure`).
        ReadSource(raw, unsafe { core::mem::transmute_copy(&(*raw).code) })
    }
}

impl ReadSource {
    /// Reads up to `max` bytes: `Ok(None)` at the end, `Err` with the stream's status byte.
    pub fn read(&self, max: usize) -> Result<Option<Vec<u8>>, u8> {
        let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
        let mut present = 0u8;
        let mut message = StrVal::owned(core::ptr::null_mut(), 0);
        // SAFETY: the code follows the `Connection.read` convention, filling `out` with an owned
        // `Bytes` when it reports a chunk; the closure is borrowed for the call.
        unsafe {
            let status = (self.1)(
                self.0,
                1,
                max as i64,
                out.as_mut_ptr(),
                &mut present,
                &mut message,
            );
            if message.owns() && !message.ptr_word.is_null() {
                crate::ffi::str_release(&message);
            }
            if status != 0 {
                return Err(status);
            }
            if present == 0 {
                return Ok(None);
            }
            let mut v = out.assume_init();
            let data = bytes_ref(&raw const v).to_vec();
            msrt_bytes_drop(&raw mut v);
            Ok(Some(data))
        }
    }
}

/// An extra result slot of a native, written through a trailing pointer parameter.
pub struct Out<'a, T: IntoAbi>(*mut T::Raw, PhantomData<&'a mut T::Raw>);

impl<T: IntoAbi> Out<'_, T> {
    pub fn write(self, v: T) {
        // SAFETY: an `Out` is only built by `from_raw`, whose caller guarantees a writable slot.
        unsafe { self.0.write(v.into_raw()) }
    }
}
impl<T: IntoAbi> AbiType for Out<'_, T> {
    type Raw = *mut T::Raw;
}
// SAFETY: the caller passes writable memory for one result slot.
unsafe impl<'a, T: IntoAbi> FromAbi<'a> for Out<'a, T> {
    unsafe fn from_raw(raw: *mut T::Raw) -> Out<'a, T> {
        Out(raw, PhantomData)
    }
}

/// A reference-counted runtime object (header followed by the Rust value), returned to Manuscript
/// as a `Shared`-class handle. The runtime drops the value when the count reaches zero. The layout
/// matches `ms_rt::glue::Handle<T>`, so crates move between the two one function at a time.
#[repr(C)]
pub struct ObjCell<T> {
    header: ms_rt_abi::Obj,
    value: T,
}

unsafe extern "C" fn cell_drop<T>(o: *mut ms_rt_abi::Obj) {
    let c = o.cast::<ObjCell<T>>();
    // SAFETY: `o` is an `ObjCell<T>` built by `Object::into_raw`; freed once, at count zero.
    unsafe {
        core::ptr::drop_in_place(&mut (*c).value);
        msrt_free(o.cast());
    }
}

/// A new runtime object owning `T`.
pub struct Object<T: AbiHandle>(pub T);
/// A borrow of the value inside a runtime object.
pub struct ObjRef<'a, T: AbiHandle>(pub &'a T);

impl<T: AbiHandle> Deref for ObjRef<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.0
    }
}
impl<T: AbiHandle> AbiType for Object<T> {
    type Raw = *mut ObjCell<T>;
}
impl<T: AbiHandle> AbiType for ObjRef<'_, T> {
    type Raw = *const ObjCell<T>;
}
impl<T: AbiHandle> IntoAbi for Object<T> {
    type Raw = *mut ObjCell<T>;
    fn into_raw(self) -> *mut ObjCell<T> {
        // SAFETY: a fresh runtime allocation, initialized before it escapes.
        unsafe {
            let p = msrt_alloc(core::mem::size_of::<ObjCell<T>>()).cast::<ObjCell<T>>();
            p.write(ObjCell {
                header: ms_rt_abi::Obj {
                    rc: 1,
                    drop: Some(cell_drop::<T>),
                },
                value: self.0,
            });
            p
        }
    }
}
// SAFETY: an object argument is a live runtime object that outlives the call.
unsafe impl<'a, T: AbiHandle> FromAbi<'a> for ObjRef<'a, T> {
    unsafe fn from_raw(raw: *const ObjCell<T>) -> ObjRef<'a, T> {
        // SAFETY: caller contract.
        ObjRef(unsafe { &(*raw).value })
    }
}

/// An exclusive borrow of the value inside a runtime object, for builders that mutate in place.
/// The caller must not use the same object elsewhere during the call.
pub struct ObjMut<'a, T: AbiHandle>(pub &'a mut T);

impl<T: AbiHandle> Deref for ObjMut<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.0
    }
}
impl<T: AbiHandle> DerefMut for ObjMut<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        self.0
    }
}
impl<T: AbiHandle> AbiType for ObjMut<'_, T> {
    type Raw = *mut ObjCell<T>;
}
// SAFETY: an object argument is a live runtime object that outlives the call and is not aliased.
unsafe impl<'a, T: AbiHandle> FromAbi<'a> for ObjMut<'a, T> {
    unsafe fn from_raw(raw: *mut ObjCell<T>) -> ObjMut<'a, T> {
        // SAFETY: caller contract.
        ObjMut(unsafe { &mut (*raw).value })
    }
}

/// A pointer to a caller-owned array whose length is a separate `n` parameter: read it with
/// [`IdArray::get`] and the `n` the same call received.
pub struct IdArray<'a>(*const u32, PhantomData<&'a u32>);

impl IdArray<'_> {
    pub fn get(&self, n: i64) -> Vec<u32> {
        let n = usize::try_from(n).unwrap_or(0);
        if n == 0 {
            return Vec::new();
        }
        // SAFETY: the generated code passes a pointer to `n` readable ids.
        unsafe { core::slice::from_raw_parts(self.0, n) }.to_vec()
    }
}
impl AbiType for IdArray<'_> {
    type Raw = *const u32;
}
// SAFETY: the caller passes a pointer to as many ids as the `n` argument it pairs with.
unsafe impl<'a> FromAbi<'a> for IdArray<'a> {
    unsafe fn from_raw(raw: *const u32) -> IdArray<'a> {
        IdArray(raw, PhantomData)
    }
}

/// Like [`IdArray`], for an array of strings.
pub struct StrArray<'a>(*const StrVal, PhantomData<&'a StrVal>);

impl<'a> StrArray<'a> {
    pub fn get(&self, n: i64) -> Vec<&'a str> {
        let n = usize::try_from(n).unwrap_or(0);
        (0..n)
            // SAFETY: the generated code passes `n` live strings.
            .map(|i| unsafe { str_ref(self.0.add(i)) })
            .collect()
    }
}
impl AbiType for StrArray<'_> {
    type Raw = *const StrVal;
}
// SAFETY: the caller passes a pointer to as many live strings as the `n` argument it pairs with.
unsafe impl<'a> FromAbi<'a> for StrArray<'a> {
    unsafe fn from_raw(raw: *const StrVal) -> StrArray<'a> {
        StrArray(raw, PhantomData)
    }
}

/// `None` is an absent `String?`.
impl IntoAbi for Option<String> {
    type Raw = OptStr;
    fn into_raw(self) -> OptStr {
        match self {
            Some(s) => OptStr {
                value: new_string(&s),
            },
            None => OptStr::NONE,
        }
    }
}

/// A Rust value handed to Manuscript as an opaque pointer (a `handle` type); declare it with
/// [`abi_handle!`]. Use [`Own`], [`Ref`] and [`Mut`] in native signatures.
///
/// # Safety
/// Only [`abi_handle!`] implements it.
pub unsafe trait AbiHandle: Sized {}

/// An owned handle: returned to Manuscript as a pointer, or received to be freed.
pub struct Own<T: AbiHandle>(pub Box<T>);
/// A shared borrow of a handle.
pub struct Ref<'a, T: AbiHandle>(pub &'a T);
/// An exclusive borrow of a handle.
pub struct Mut<'a, T: AbiHandle>(pub &'a mut T);

impl<T: AbiHandle> Deref for Own<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}
impl<T: AbiHandle> Deref for Ref<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.0
    }
}
impl<T: AbiHandle> Deref for Mut<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.0
    }
}
impl<T: AbiHandle> DerefMut for Mut<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        self.0
    }
}

impl<T: AbiHandle> AbiType for Own<T> {
    type Raw = *mut T;
}
impl<T: AbiHandle> AbiType for Ref<'_, T> {
    type Raw = *const T;
}
impl<T: AbiHandle> AbiType for Mut<'_, T> {
    type Raw = *mut T;
}
// SAFETY: an owned handle came from `into_raw` and is received once.
unsafe impl<T: AbiHandle> FromAbi<'_> for Own<T> {
    unsafe fn from_raw(raw: *mut T) -> Own<T> {
        // SAFETY: caller contract.
        Own(unsafe { Box::from_raw(raw) })
    }
}
// SAFETY: a handle argument is a live handle.
unsafe impl<'a, T: AbiHandle> FromAbi<'a> for Ref<'a, T> {
    unsafe fn from_raw(raw: *const T) -> Ref<'a, T> {
        // SAFETY: caller contract.
        Ref(unsafe { &*raw })
    }
}
// SAFETY: a handle argument is a live handle with no other borrow during the call.
unsafe impl<'a, T: AbiHandle> FromAbi<'a> for Mut<'a, T> {
    unsafe fn from_raw(raw: *mut T) -> Mut<'a, T> {
        // SAFETY: caller contract.
        Mut(unsafe { &mut *raw })
    }
}
impl<T: AbiHandle> IntoAbi for Own<T> {
    type Raw = *mut T;
    fn into_raw(self) -> *mut T {
        Box::into_raw(self.0)
    }
}

/// Declares a Rust type as a handle for [`native!`](crate::native).
#[macro_export]
macro_rules! abi_handle {
    ($t:ty) => {
        #[allow(unsafe_code)]
        // SAFETY: handles cross the ABI only through `Own`, `Ref` and `Mut`.
        unsafe impl $crate::ffi::AbiHandle for $t {}
    };
}

/// A `repr(C)` record whose fields are all [`AbiSlot`]s; declare it with [`abi_record!`].
///
/// # Safety
/// The type is `repr(C)` with the layout of the Manuscript record and every field is an
/// [`AbiSlot`]. Only [`abi_record!`] implements it.
pub unsafe trait AbiRecord: Sized {
    /// The slot descriptor of the record, for `List[Record]`.
    fn desc() -> &'static TypeDesc;
}

impl<R: AbiRecord> AbiType for &R {
    type Raw = *const R;
}
// SAFETY: record arguments are live records that outlive the call.
unsafe impl<'a, R: AbiRecord> FromAbi<'a> for &'a R {
    unsafe fn from_raw(raw: *const R) -> &'a R {
        // SAFETY: caller contract.
        unsafe { &*raw }
    }
}
impl<R: AbiRecord> IntoAbi for R {
    type Raw = R;
    fn into_raw(self) -> R {
        self
    }
}

/// Declares a record type shared with generated code: a `repr(C)` struct whose fields are all
/// [`AbiSlot`](crate::ffi::AbiSlot)s, usable as `&Rec` arguments and `-> Rec` / `-> out Rec` results of
/// [`native!`](crate::native).
///
/// The compiler flattens a record into its fields' leaves with no padding of its own, so a field
/// declared after a nested record sits right behind the nested record's last leaf, not at its
/// padded `repr(C)` size. Where a field follows a nested record, list the nested fields inline
/// and test the offset of the field after them with `offset_of!`.
#[macro_export]
macro_rules! abi_record {
    (
        $(#[$m:meta])*
        $vis:vis struct $name:ident { $($fvis:vis $f:ident: $t:ty),* $(,)? }
    ) => {
        $(#[$m])*
        #[repr(C)]
        $vis struct $name { $($fvis $f: $t),* }
        #[allow(unsafe_code)]
        // A record nested in another record is itself a slot.
        impl $crate::ffi::AbiSlot for $name {
            unsafe fn release(&mut self) {
                // SAFETY: caller contract; every field is a live slot.
                $(unsafe { $crate::ffi::AbiSlot::release(&mut self.$f) };)*
            }
            unsafe fn duplicate(&self) -> $name {
                // SAFETY: caller contract.
                $name { $($f: unsafe { $crate::ffi::AbiSlot::duplicate(&self.$f) }),* }
            }
        }
        #[allow(unsafe_code)]
        // SAFETY: `repr(C)` above; every field is an `AbiSlot` (a bound of the calls below).
        unsafe impl $crate::ffi::AbiRecord for $name {
            fn desc() -> &'static $crate::ffi::TypeDesc {
                // SAFETY (both fns): the runtime passes live slots of this record type.
                unsafe extern "C" fn release(slot: *mut u8) {
                    let r = unsafe { &mut *slot.cast::<$name>() };
                    $(unsafe { $crate::ffi::AbiSlot::release(&mut r.$f) };)*
                }
                unsafe extern "C" fn duplicate(src: *const u8, dst: *mut u8) {
                    let r = unsafe { &*src.cast::<$name>() };
                    unsafe {
                        dst.cast::<$name>().write($name {
                            $($f: $crate::ffi::AbiSlot::duplicate(&r.$f)),*
                        })
                    };
                }
                static DESC: $crate::ffi::TypeDesc = $crate::ffi::TypeDesc {
                    size: ::core::mem::size_of::<$name>() as u32,
                    align: ::core::mem::align_of::<$name>() as u32,
                    kind: $crate::ffi::KIND_CUSTOM,
                    reserved: 0,
                    inner0: ::core::ptr::null(),
                    inner1: ::core::ptr::null(),
                    drop: Some(release),
                    copy: Some(duplicate),
                    eq: None,
                    hash: None,
                };
                &DESC
            }
        }
    };
}

/// Defines native entry points from safe signatures.
///
/// ```ignore
/// native! {
///     fn msrt_path_basename(windows: bool, path: &str) -> String { rules(windows).basename(path) }
///     fn msrt_path_relative(windows: bool, base: &str, target: &str) -> Result<String, InvalidInput> { .. }
///     fn msrt_path_parse(windows: bool, path: &str) -> out PartsRec { .. }
/// }
/// ```
///
/// Each item becomes `#[no_mangle] pub unsafe extern "C" fn` (`safe fn` drops the `unsafe` for
/// scalar-only signatures): arguments convert with
/// [`FromAbi`], the body is an ordinary safe function, and the result converts with
/// [`IntoAbi`]. `Result<T, E>` appends `out: *mut T::Raw` and returns `E`'s [`Status`] byte
/// (`STATUS_OK` on success). `-> out T` appends `out: *mut T::Raw` and returns nothing.
#[macro_export]
macro_rules! native {
    () => {};
    // `safe fn`: every parameter and the result are scalars, so the shim itself is safe to call.
    (
        $(#[$m:meta])*
        safe fn $name:ident($($p:ident: $t:ty),* $(,)?) -> $($tail:tt)*
    ) => {
        $crate::native! { @item [] $(#[$m])* fn $name($($p: $t),*) -> $($tail)* }
    };
    (
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> $($tail:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> $($tail)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Result<(), $err:ty> $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name($($p: <$t as $crate::ffi::AbiType>::Raw),*) -> u8 {
            fn native_body($($p: $t),*) -> Result<(), $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            match native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*) {
                Ok(()) => $crate::ffi::STATUS_OK,
                Err(e) => $crate::ffi::Status::status(e),
            }
        }
        $crate::native! { $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Result<($a:ty, $b:ty), $err:ty> $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name(
            $($p: <$t as $crate::ffi::AbiType>::Raw,)*
            out: *mut <$a as $crate::ffi::IntoAbi>::Raw,
            out2: *mut <$b as $crate::ffi::IntoAbi>::Raw,
        ) -> u8 {
            fn native_body($($p: $t),*) -> Result<($a, $b), $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let r = native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*);
            match r {
                Ok((x, y)) => {
                    // SAFETY: `out` and `out2` are writable for one result slot each.
                    unsafe {
                        out.write($crate::ffi::IntoAbi::into_raw(x));
                        out2.write($crate::ffi::IntoAbi::into_raw(y));
                    }
                    $crate::ffi::STATUS_OK
                }
                Err(e) => $crate::ffi::Status::status(e),
            }
        }
        $crate::native! { $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Result<$ok:ty, $err:ty> $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name(
            $($p: <$t as $crate::ffi::AbiType>::Raw,)*
            out: *mut <$ok as $crate::ffi::IntoAbi>::Raw,
        ) -> u8 {
            fn native_body($($p: $t),*) -> Result<$ok, $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let r = native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*);
            match r {
                Ok(v) => {
                    // SAFETY: `out` is writable for one result slot by the caller contract.
                    unsafe { out.write($crate::ffi::IntoAbi::into_raw(v)) };
                    $crate::ffi::STATUS_OK
                }
                Err(e) => $crate::ffi::Status::status(e),
            }
        }
        $crate::native! { $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> out ($a:ty, $b:ty) $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name(
            $($p: <$t as $crate::ffi::AbiType>::Raw,)*
            out: *mut <$a as $crate::ffi::IntoAbi>::Raw,
            out2: *mut <$b as $crate::ffi::IntoAbi>::Raw,
        ) {
            fn native_body($($p: $t),*) -> ($a, $b) $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let (x, y) = native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*);
            // SAFETY: `out` and `out2` are writable for one result slot each.
            unsafe {
                out.write($crate::ffi::IntoAbi::into_raw(x));
                out2.write($crate::ffi::IntoAbi::into_raw(y));
            }
        }
        $crate::native! { $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> out $res:ty $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name(
            $($p: <$t as $crate::ffi::AbiType>::Raw,)*
            out: *mut <$res as $crate::ffi::IntoAbi>::Raw,
        ) {
            fn native_body($($p: $t),*) -> $res $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let v = native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*);
            // SAFETY: `out` is writable for one result slot by the caller contract.
            unsafe { out.write($crate::ffi::IntoAbi::into_raw(v)) };
        }
        $crate::native! { $($rest)* }
    };
    // Strings are three words: they come back through a trailing out-pointer, like lists.
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> String $body:block
        $($rest:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> out String $body $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> &'static str $body:block
        $($rest:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> out &'static str $body $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> &str $body:block
        $($rest:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> out &str $body $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Text $body:block
        $($rest:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> out Text $body $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Option<String> $body:block
        $($rest:tt)*
    ) => {
        $crate::native! { @item [unsafe] $(#[$m])* fn $name($($p: $t),*) -> out Option<String> $body $($rest)* }
    };
    (
        @item [$($q:tt)*]
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> $ret:ty $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C-unwind" fn $name(
            $($p: <$t as $crate::ffi::AbiType>::Raw),*
        ) -> <$ret as $crate::ffi::IntoAbi>::Raw {
            const {
                assert!(
                    ::core::mem::size_of::<<$ret as $crate::ffi::IntoAbi>::Raw>() <= 8,
                    "results wider than a word return through `-> out`"
                )
            };
            fn native_body($($p: $t),*) -> $ret $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            $crate::ffi::IntoAbi::into_raw(native_body($(unsafe { <$t as $crate::ffi::FromAbi>::from_raw($p) }),*))
        }
        $crate::native! { $($rest)* }
    };
}
