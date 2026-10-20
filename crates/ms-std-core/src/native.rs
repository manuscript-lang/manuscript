//! Safe native signatures: the [`native!`](crate::native) macro generates the `extern "C"` shim
//! from a safe Rust signature, so native bodies hold no `unsafe` and the pointer conversions live
//! here, once.
//!
//! Parameter types implement [`FromAbi`], results [`IntoAbi`], and error types [`Status`]. A
//! fallible native (`-> Result<T, E>`) returns the status byte and writes `T` through a trailing
//! out-pointer; a record result (`-> out T`) is written through a trailing out-pointer and the
//! shim returns nothing. This is the same layout the hand-written shims used.
use crate::{Fail, StrObj, VecVal, bytes_ref, new_string, read_string_list, str_ref};
use alloc::string::String;
use alloc::vec::Vec;

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
scalar!(i64, f64, u8);

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
/// Each item becomes `#[no_mangle] pub unsafe extern "C" fn`: arguments convert with
/// [`FromAbi`], the body is an ordinary safe function, and the result converts with
/// [`IntoAbi`]. `Result<T, E>` appends `out: *mut T::Raw` and returns `E`'s [`Status`] byte
/// (`STATUS_OK` on success). `-> out T` appends `out: *mut T::Raw` and returns nothing.
#[macro_export]
macro_rules! native {
    () => {};
    (
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> Result<$ok:ty, $err:ty> $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc)]
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
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
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> out $res:ty $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc)]
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
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
        $(#[$m:meta])*
        fn $name:ident($($p:ident: $t:ty),* $(,)?) -> $ret:ty $body:block
        $($rest:tt)*
    ) => {
        $(#[$m])*
        #[allow(unsafe_code, clippy::missing_safety_doc)]
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
            $($p: <$t as $crate::AbiType>::Raw),*
        ) -> <$ret as $crate::IntoAbi>::Raw {
            fn body($($p: $t),*) -> $ret $body
            // SAFETY: arguments are live values of their declared types (`FromAbi`).
            $crate::IntoAbi::into_raw(body($(unsafe { <$t as $crate::FromAbi>::from_raw($p) }),*))
        }
        $crate::native! { $($rest)* }
    };
}
