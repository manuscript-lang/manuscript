//! Safe native signatures: the [`native!`](crate::native) macro generates the `extern "C"` shim
//! from a safe Rust signature, so native bodies hold no `unsafe` and the pointer conversions live
//! here, once.
//!
//! Parameter types implement [`FromAbi`], results [`IntoAbi`], and error types [`Status`]. A
//! fallible native (`-> Result<T, E>`) returns the status byte and writes `T` through a trailing
//! out-pointer; a record result (`-> out T`) is written through a trailing out-pointer and the
//! shim returns nothing. This is the same layout the hand-written shims used.
use crate::{
    Fail, StrObj, TypeDesc, VecVal, bytes_ref, new_string, new_string_bytes, read_string_list,
    str_ref, write_bytes,
};
use alloc::boxed::Box;
use alloc::string::String;
use alloc::vec::Vec;
use core::marker::PhantomData;
use core::ops::{Deref, DerefMut};
use ms_rt_abi::{Closure, MapVal};

unsafe extern "C" {
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
    fn msrt_map_new(out: *mut MapVal);
    fn msrt_map_add(
        m: *mut MapVal,
        kd: *const TypeDesc,
        vd: *const TypeDesc,
        k: *mut u8,
        v: *mut u8,
    );
    static msrt_desc_int: TypeDesc;
    fn msrt_bytes_drop(b: *mut VecVal);
    fn msrt_bytes_copy(b: *const VecVal, out: *mut VecVal);
    fn msrt_list_new(out: *mut VecVal);
    fn msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8);
    fn msrt_list_drop(v: *mut VecVal, d: *const TypeDesc);
    fn msrt_list_copy(v: *const VecVal, d: *const TypeDesc, out: *mut VecVal);
    static msrt_desc_string: TypeDesc;
}

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
scalar!(i64, f64, u8, u32, u64);

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
    type Raw = *const StrObj;
}
// SAFETY: `String` arguments are live, non-null `StrObj`s that outlive the call.
unsafe impl<'a> FromAbi<'a> for &'a str {
    unsafe fn from_raw(raw: *const StrObj) -> &'a str {
        // SAFETY: caller contract.
        unsafe { str_ref(raw) }
    }
}
impl IntoAbi for &str {
    type Raw = *mut StrObj;
    fn into_raw(self) -> *mut StrObj {
        new_string(self)
    }
}
impl IntoAbi for String {
    type Raw = *mut StrObj;
    fn into_raw(self) -> *mut StrObj {
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
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_bytes` initializes `v`.
        unsafe {
            crate::write_bytes(v.as_mut_ptr(), &self);
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

/// A record of `N` strings (all fields `String`), laid out as `N` consecutive pointers.
impl<const N: usize> AbiType for [&str; N] {
    type Raw = *const [*mut StrObj; N];
}
// SAFETY: record arguments are live records of `N` live strings that outlive the call.
unsafe impl<'a, const N: usize> FromAbi<'a> for [&'a str; N] {
    unsafe fn from_raw(raw: *const [*mut StrObj; N]) -> [&'a str; N] {
        // SAFETY: caller contract; each field is a live string.
        unsafe { (*raw).map(|p| str_ref(p)) }
    }
}
impl<const N: usize> IntoAbi for [String; N] {
    type Raw = [*mut StrObj; N];
    fn into_raw(self) -> [*mut StrObj; N] {
        self.map(|s| new_string(&s))
    }
}

/// An owned runtime string stored inside a record (`String` field), for [`abi_record!`].
/// Dropping it does not free the string: the record's owner does that.
#[repr(transparent)]
pub struct Str(*mut StrObj);

impl Str {
    pub fn new(s: &str) -> Str {
        Str(new_string(s))
    }

    /// A string made from host bytes the caller trusts to be text.
    pub fn from_bytes(b: &[u8]) -> Str {
        Str(new_string_bytes(b))
    }

    pub fn as_ptr(&self) -> *const StrObj {
        self.0
    }

    pub fn as_str(&self) -> &str {
        // SAFETY: a `Str` is only created by `new` or by the runtime inside a live record.
        unsafe { str_ref(self.0) }
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
            crate::write_string_list(v.as_mut_ptr(), items);
            StringList(v.assume_init())
        }
    }

    pub fn to_vec(&self) -> Vec<&str> {
        // SAFETY: a `StringList` is only created by `new` or by the runtime inside a live record.
        unsafe { read_string_list(&raw const self.0) }
    }
}

/// A string result held as bytes, for host text that is checked (or trusted) to be UTF-8 by the
/// native rather than by the type.
pub struct Text(pub Vec<u8>);

impl IntoAbi for Text {
    type Raw = *mut StrObj;
    fn into_raw(self) -> *mut StrObj {
        new_string_bytes(&self.0)
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
                msrt_list_push(out.as_mut_ptr(), crate::desc_bytes(), v.as_ptr().cast());
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

type PairCode = unsafe extern "C-unwind" fn(*mut Closure, *const StrObj, *const StrObj) -> u8;
type EntryCode =
    unsafe extern "C-unwind" fn(*mut Closure, *const StrObj, *const StrObj, u8, u8) -> u8;

/// Calls `code` with temporary strings made from `bytes`, released after the call.
fn with_strings<R>(bytes: [&[u8]; 2], call: impl FnOnce(*const StrObj, *const StrObj) -> R) -> R {
    let (a, b) = (new_string_bytes(bytes[0]), new_string_bytes(bytes[1]));
    let r = call(a, b);
    // SAFETY: the callee only borrowed the strings; this releases the one reference made above.
    unsafe {
        msrt_release(a.cast());
        msrt_release(b.cast());
    }
    r
}

/// A nullable compiled closure over two strings, answering a bool (`copy`'s filter).
pub struct PairFilter(*mut Closure, PairCode);

impl PairFilter {
    pub fn call(&self, a: &[u8], b: &[u8]) -> bool {
        // SAFETY: the compiler built the closure with this signature (`FromAbi`).
        with_strings([a, b], |a, b| unsafe { (self.1)(self.0, a, b) } != 0)
    }
}

/// A nullable compiled closure over `(path, name, directory, symlink)` (`glob`'s exclusion).
pub struct EntryFilter(*mut Closure, EntryCode);

impl EntryFilter {
    pub fn call(&self, path: &[u8], name: &[u8], directory: bool, symlink: bool) -> bool {
        // SAFETY: the compiler built the closure with this signature (`FromAbi`).
        with_strings(
            [path, name],
            |p, n| unsafe { (self.1)(self.0, p, n, u8::from(directory), u8::from(symlink)) } != 0,
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

    pub fn get(&self) -> &T {
        &self.0
    }
}

// SAFETY: the runtime runs Manuscript code on one thread, the only one that reaches a `Global`.
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
plain_slot!(i64, f64, u8, u32, u64, OptInt);

/// `Optional[Int]` stored inline in a record: a presence byte, then the value.
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
        unsafe { msrt_release(self.0.cast()) }
    }
    unsafe fn duplicate(&self) -> Str {
        // SAFETY: caller contract.
        unsafe { msrt_retain(self.0.cast()) };
        Str(self.0)
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
impl IntoAbi for *mut StrObj {
    type Raw = *mut StrObj;
    fn into_raw(self) -> *mut StrObj {
        self
    }
}

// SAFETY: an optional `String` argument is a live string or null.
unsafe impl<'a> FromAbi<'a> for Option<&'a str> {
    unsafe fn from_raw(raw: *const StrObj) -> Option<&'a str> {
        // SAFETY: caller contract.
        (!raw.is_null()).then(|| unsafe { str_ref(raw) })
    }
}
impl AbiType for Option<&str> {
    type Raw = *const StrObj;
}

impl AbiType for Vec<Vec<&str>> {
    type Raw = *const VecVal;
}
// SAFETY: `List[List[String]]` arguments are live and outlive the call.
unsafe impl<'a> FromAbi<'a> for Vec<Vec<&'a str>> {
    unsafe fn from_raw(raw: *const VecVal) -> Vec<Vec<&'a str>> {
        // SAFETY: caller contract.
        unsafe { crate::read_string_matrix(raw) }
    }
}
impl IntoAbi for Vec<Vec<String>> {
    type Raw = VecVal;
    fn into_raw(self) -> VecVal {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_string_matrix` initializes `v`.
        unsafe {
            crate::write_string_matrix(
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
            crate::write_string_list(v.as_mut_ptr(), &self);
            v.assume_init()
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
/// matches `ms_std_rt::Handle<T>`, so crates move between the two one function at a time.
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

/// Like [`IdArray`], for an array of string pointers.
pub struct StrArray<'a>(*const *const StrObj, PhantomData<&'a StrObj>);

impl<'a> StrArray<'a> {
    pub fn get(&self, n: i64) -> Vec<&'a str> {
        let n = usize::try_from(n).unwrap_or(0);
        (0..n)
            // SAFETY: the generated code passes `n` live strings.
            .map(|i| unsafe { str_ref(*self.0.add(i)) })
            .collect()
    }
}
impl AbiType for StrArray<'_> {
    type Raw = *const *const StrObj;
}
// SAFETY: the caller passes a pointer to as many live strings as the `n` argument it pairs with.
unsafe impl<'a> FromAbi<'a> for StrArray<'a> {
    unsafe fn from_raw(raw: *const *const StrObj) -> StrArray<'a> {
        StrArray(raw, PhantomData)
    }
}

/// `None` becomes a null string pointer.
impl IntoAbi for Option<String> {
    type Raw = *mut StrObj;
    fn into_raw(self) -> *mut StrObj {
        self.map_or(core::ptr::null_mut(), |s| new_string(&s))
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
        unsafe impl $crate::AbiHandle for $t {}
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
/// [`AbiSlot`](crate::AbiSlot)s, usable as `&Rec` arguments and `-> Rec` / `-> out Rec` results of
/// [`native!`](crate::native).
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
        // SAFETY: `repr(C)` above; every field is an `AbiSlot` (a bound of the calls below).
        unsafe impl $crate::AbiRecord for $name {
            fn desc() -> &'static $crate::TypeDesc {
                // SAFETY (both fns): the runtime passes live slots of this record type.
                unsafe extern "C" fn release(slot: *mut u8) {
                    let r = unsafe { &mut *slot.cast::<$name>() };
                    $(unsafe { $crate::AbiSlot::release(&mut r.$f) };)*
                }
                unsafe extern "C" fn duplicate(src: *const u8, dst: *mut u8) {
                    let r = unsafe { &*src.cast::<$name>() };
                    unsafe {
                        dst.cast::<$name>().write($name {
                            $($f: $crate::AbiSlot::duplicate(&r.$f)),*
                        })
                    };
                }
                static DESC: $crate::TypeDesc = $crate::TypeDesc {
                    size: ::core::mem::size_of::<$name>() as u32,
                    align: ::core::mem::align_of::<$name>() as u32,
                    kind: $crate::KIND_CUSTOM,
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
        pub $($q)* extern "C-unwind" fn $name($($p: <$t as $crate::AbiType>::Raw),*) -> u8 {
            fn body($($p: $t),*) -> Result<(), $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            match body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*) {
                Ok(()) => $crate::STATUS_OK,
                Err(e) => $crate::Status::status(e),
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
            $($p: <$t as $crate::AbiType>::Raw,)*
            out: *mut <$a as $crate::IntoAbi>::Raw,
            out2: *mut <$b as $crate::IntoAbi>::Raw,
        ) -> u8 {
            fn body($($p: $t),*) -> Result<($a, $b), $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let r = body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*);
            match r {
                Ok((x, y)) => {
                    // SAFETY: `out` and `out2` are writable for one result slot each.
                    unsafe {
                        out.write($crate::IntoAbi::into_raw(x));
                        out2.write($crate::IntoAbi::into_raw(y));
                    }
                    $crate::STATUS_OK
                }
                Err(e) => $crate::Status::status(e),
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
            $($p: <$t as $crate::AbiType>::Raw,)*
            out: *mut <$ok as $crate::IntoAbi>::Raw,
        ) -> u8 {
            fn body($($p: $t),*) -> Result<$ok, $err> $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let r = body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*);
            match r {
                Ok(v) => {
                    // SAFETY: `out` is writable for one result slot by the caller contract.
                    unsafe { out.write($crate::IntoAbi::into_raw(v)) };
                    $crate::STATUS_OK
                }
                Err(e) => $crate::Status::status(e),
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
            $($p: <$t as $crate::AbiType>::Raw,)*
            out: *mut <$a as $crate::IntoAbi>::Raw,
            out2: *mut <$b as $crate::IntoAbi>::Raw,
        ) {
            fn body($($p: $t),*) -> ($a, $b) $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let (x, y) = body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*);
            // SAFETY: `out` and `out2` are writable for one result slot each.
            unsafe {
                out.write($crate::IntoAbi::into_raw(x));
                out2.write($crate::IntoAbi::into_raw(y));
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
            $($p: <$t as $crate::AbiType>::Raw,)*
            out: *mut <$res as $crate::IntoAbi>::Raw,
        ) {
            fn body($($p: $t),*) -> $res $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            let v = body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*);
            // SAFETY: `out` is writable for one result slot by the caller contract.
            unsafe { out.write($crate::IntoAbi::into_raw(v)) };
        }
        $crate::native! { $($rest)* }
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
            $($p: <$t as $crate::AbiType>::Raw),*
        ) -> <$ret as $crate::IntoAbi>::Raw {
            fn body($($p: $t),*) -> $ret $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            $crate::IntoAbi::into_raw(body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*))
        }
        $crate::native! { $($rest)* }
    };
}
