//! Builds a tree of one recursive alternative (such as `JsonValue`) from parse events.
//!
//! The alternative's layout belongs to the compiler, so the compiler passes a constructor thunk:
//! `ctor(kind, payload, out)` moves the payload (a `Bool` byte, a `String`, a list or a
//! `String`-keyed map of the alternative) into a new value of the case `kind` written at `out`.
//! Completed values wait on one stack, `size` bytes each; closing a container moves its children
//! into a list or map and builds the container's own value.
use crate::alloc;
use crate::desc::{msrt_desc_string, slot_drop};
use crate::ffi::{AbiType, FromAbi};
use crate::map;
use crate::string::from_bytes;
use core::marker::PhantomData;
use core::mem::MaybeUninit;
use ms_rt_abi::{StrVal, TypeDesc, VecVal};
use ms_rt_hot::Layout;
use std::vec::Vec;

pub const NULL: i64 = 0;
pub const BOOL: i64 = 1;
pub const NUMBER: i64 = 2;
pub const STRING: i64 = 3;
pub const ARRAY: i64 = 4;
pub const OBJECT: i64 = 5;

/// The compiler's constructor thunk, see the module docs.
pub type Ctor = unsafe extern "C-unwind" fn(kind: i64, payload: *mut u8, out: *mut u8) -> i64;

/// The descriptor of the alternative, as a native argument.
pub struct ValueDesc<'a>(&'a TypeDesc);

impl AbiType for ValueDesc<'_> {
    type Raw = *const TypeDesc;
}
// SAFETY: the compiler passes the static descriptor of the alternative.
unsafe impl<'a> FromAbi<'a> for ValueDesc<'a> {
    unsafe fn from_raw(raw: *const TypeDesc) -> ValueDesc<'a> {
        // SAFETY: caller contract.
        ValueDesc(unsafe { &*raw })
    }
}

/// The constructor thunk, as a native argument.
pub struct TreeCtor(Ctor);

impl AbiType for TreeCtor {
    type Raw = Ctor;
}
// SAFETY: the compiler passes a thunk with the [`Ctor`] signature.
unsafe impl FromAbi<'_> for TreeCtor {
    unsafe fn from_raw(raw: Ctor) -> TreeCtor {
        TreeCtor(raw)
    }
}

/// A slot for one value of the alternative, as a native argument.
pub struct ValueOut<'a>(*mut u8, PhantomData<&'a mut u8>);

impl AbiType for ValueOut<'_> {
    type Raw = *mut u8;
}
// SAFETY: the caller passes writable memory for one value of the alternative.
unsafe impl<'a> FromAbi<'a> for ValueOut<'a> {
    unsafe fn from_raw(raw: *mut u8) -> ValueOut<'a> {
        ValueOut(raw, PhantomData)
    }
}

pub struct TreeBuilder<'a> {
    desc: &'a TypeDesc,
    /// Layout of a `String`-keyed map of the values.
    map_layout: Layout,
    ctor: Ctor,
    /// Words per value.
    words: usize,
    /// Completed values not yet moved into a container.
    vals: Vec<MaybeUninit<u64>>,
    /// Keys of the open objects' members so far.
    keys: Vec<StrVal>,
    /// `(vals, keys)` lengths where each open container began.
    marks: Vec<(usize, usize)>,
}

impl<'a> TreeBuilder<'a> {
    pub fn new(desc: ValueDesc<'a>, ctor: TreeCtor, capacity: usize) -> TreeBuilder<'a> {
        let desc = desc.0;
        let size = desc.size as usize;
        assert!(
            desc.align <= 8 && size.is_multiple_of(8),
            "tree value layout"
        );
        let words = size / 8;
        TreeBuilder {
            desc,
            map_layout: map::string_map_layout(desc),
            ctor: ctor.0,
            words,
            vals: Vec::with_capacity(capacity * words),
            keys: Vec::new(),
            marks: Vec::new(),
        }
    }

    /// Room for one more value on the stack, to be written by the caller; returns its address.
    fn push_slot(&mut self) -> *mut u8 {
        let at = self.vals.len();
        self.vals.reserve(self.words);
        // SAFETY: the room is reserved; the value is written before anything reads it, and
        // `MaybeUninit` words may hold anything.
        unsafe {
            self.vals.set_len(at + self.words);
            self.vals.as_mut_ptr().add(at).cast()
        }
    }

    fn scalar(&mut self, kind: i64, payload: *mut u8) {
        let out = self.push_slot();
        // SAFETY: the thunk writes one value at `out` from a payload of the kind's type.
        unsafe { (self.ctor)(kind, payload, out) };
    }

    pub fn null(&mut self) {
        self.scalar(NULL, core::ptr::null_mut());
    }

    pub fn boolean(&mut self, v: bool) {
        let mut b = u8::from(v);
        self.scalar(BOOL, &raw mut b);
    }

    fn text(&mut self, kind: i64, s: &str) {
        let mut v = from_bytes(s.as_bytes());
        self.scalar(kind, (&raw mut v).cast());
    }

    pub fn number(&mut self, s: &str) {
        self.text(NUMBER, s);
    }

    pub fn string(&mut self, s: &str) {
        self.text(STRING, s);
    }

    pub fn key(&mut self, s: &str) {
        self.keys.push(from_bytes(s.as_bytes()));
    }

    pub fn begin_array(&mut self) {
        self.marks.push((self.vals.len(), self.keys.len()));
    }

    pub fn begin_object(&mut self) {
        self.marks.push((self.vals.len(), self.keys.len()));
    }

    pub fn end_array(&mut self) {
        let (from, _) = self.marks.pop().expect("open array");
        let n = (self.vals.len() - from) / self.words;
        let mut list = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        if n > 0 {
            let bytes = n * self.desc.size as usize;
            list.ptr = alloc::alloc(bytes);
            // SAFETY: the completed children move into the new buffer.
            unsafe {
                core::ptr::copy_nonoverlapping(self.vals.as_ptr().add(from).cast(), list.ptr, bytes)
            };
            list.len = n;
            list.cap = n;
        }
        self.vals.truncate(from);
        self.scalar(ARRAY, (&raw mut list).cast());
    }

    /// Closes the object; false when two members share a key (everything is released).
    pub fn end_object(&mut self) -> bool {
        let (from, key_from) = self.marks.pop().expect("open object");
        let n = self.keys.len() - key_from;
        let mut m = map::empty();
        m.desc = &msrt_desc_string;
        // SAFETY: the keys and values are live completed slots, consumed by the fill up to the
        // position it returns; the rest are released here.
        let repeated = unsafe {
            let keys = self.keys.as_mut_ptr().add(key_from);
            let vals: *mut u8 = self.vals.as_mut_ptr().add(from).cast();
            let stride = self.words * 8;
            match map::fill_strings(&mut m, &self.map_layout, keys, vals, stride, n) {
                Ok(()) => None,
                Err(at) => {
                    map::drop_map(&raw mut m, &msrt_desc_string, Some(self.desc));
                    for i in at..n {
                        slot_drop(&msrt_desc_string, keys.add(i).cast());
                        slot_drop(self.desc, vals.add(i * stride));
                    }
                    Some(at)
                }
            }
        };
        self.keys.truncate(key_from);
        self.vals.truncate(from);
        if repeated.is_some() {
            return false;
        }
        self.scalar(OBJECT, (&raw mut m).cast());
        true
    }

    /// Moves the one completed value to `out`.
    pub fn finish(mut self, out: ValueOut<'_>) {
        assert!(
            self.vals.len() == self.words && self.marks.is_empty(),
            "one tree root"
        );
        // SAFETY: `out` has room for one value; the stack's copy is forgotten below.
        unsafe { core::ptr::copy_nonoverlapping(self.vals.as_ptr().cast(), out.0, self.words * 8) };
        self.vals.clear();
    }
}

impl Drop for TreeBuilder<'_> {
    fn drop(&mut self) {
        // SAFETY: every stacked value and key is live and owned here.
        unsafe {
            for i in 0..self.vals.len() / self.words {
                slot_drop(self.desc, self.vals.as_mut_ptr().add(i * self.words).cast());
            }
            for k in &mut self.keys {
                slot_drop(&msrt_desc_string, (k as *mut StrVal).cast());
            }
        }
    }
}
