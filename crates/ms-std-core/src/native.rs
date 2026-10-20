//! Safe native signatures: the [`native!`](crate::native) macro generates the `extern "C"` shim
//! from a safe Rust signature, so native bodies hold no `unsafe` and the pointer conversions live
//! here, once.
//!
//! Parameter types implement [`FromAbi`], results [`IntoAbi`], and error types [`Status`]. A
//! fallible native (`-> Result<T, E>`) returns the status byte and writes `T` through a trailing
//! out-pointer; a record result (`-> out T`) is written through a trailing out-pointer and the
//! shim returns nothing. This is the same layout the hand-written shims used.
use crate::{Fail, StrObj, TypeDesc, VecVal, bytes_ref, new_string, read_string_list, str_ref};
use alloc::boxed::Box;
use alloc::string::String;
use alloc::vec::Vec;
use core::marker::PhantomData;
use core::ops::{Deref, DerefMut};

unsafe extern "C" {
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
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

/// A reference-counted runtime object (header plus a pointer to a boxed Rust value), returned to
/// Manuscript as a `Shared`-class handle. The runtime frees the value when the count reaches zero.
#[repr(C)]
pub struct ObjCell<T> {
    header: ms_rt_abi::Obj,
    state: *mut T,
}

unsafe extern "C" fn cell_drop<T>(o: *mut ms_rt_abi::Obj) {
    let c = o.cast::<ObjCell<T>>();
    // SAFETY: `o` is an `ObjCell<T>` built by `Object::into_raw`; freed once, at count zero.
    unsafe {
        drop(Box::from_raw((*c).state));
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
                state: Box::into_raw(Box::new(self.0)),
            });
            p
        }
    }
}
// SAFETY: an object argument is a live runtime object that outlives the call.
unsafe impl<'a, T: AbiHandle> FromAbi<'a> for ObjRef<'a, T> {
    unsafe fn from_raw(raw: *const ObjCell<T>) -> ObjRef<'a, T> {
        // SAFETY: caller contract.
        ObjRef(unsafe { &*(*raw).state })
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
        pub $($q)* extern "C" fn $name($($p: <$t as $crate::AbiType>::Raw),*) -> u8 {
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
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Result<$ok:ty, $err:ty> $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C" fn $name(
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
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> out $res:ty $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc, clippy::too_many_arguments)]
        #[unsafe(no_mangle)]
        pub $($q)* extern "C" fn $name(
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
        pub $($q)* extern "C" fn $name(
            $($p: <$t as $crate::AbiType>::Raw),*
        ) -> <$ret as $crate::IntoAbi>::Raw {
            fn body($($p: $t),*) -> $ret $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            $crate::IntoAbi::into_raw(body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*))
        }
        $crate::native! { $($rest)* }
    };
}
