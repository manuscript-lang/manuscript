//! Builds a tree of one recursive alternative (such as `JsonValue`) from parse events.
//!
//! The alternative's layout belongs to the compiler, so the compiler passes a constructor thunk:
//! `ctor(kind, payload, out)` moves the payload (a `Bool` byte, a `String`, a list or a
//! `String`-keyed map of the alternative) into a new value of the case `kind` written at `out`.
//! Completed values wait on one stack, `size` bytes each; closing a container moves its children
//! into a list or map and builds the container's own value.
use crate::alloc;
use crate::desc::{msrt_desc_string, slot_drop};
use crate::ffi::{AbiHandle, AbiType, FromAbi, ObjCell, ObjMut};
use crate::map;
use crate::string::from_bytes;
use core::marker::PhantomData;
use core::mem::MaybeUninit;
use ms_rt_abi::{StrVal, TypeDesc, VecVal};
use ms_rt_hot::{LIVE, Layout};
use std::vec::Vec;

pub const NULL: i64 = 0;
pub const BOOL: i64 = 1;
pub const NUMBER: i64 = 2;
pub const STRING: i64 = 3;
pub const ARRAY: i64 = 4;
pub const OBJECT: i64 = 5;

/// The compiler's constructor thunk, see the module docs.
pub type Ctor = unsafe extern "C-unwind" fn(kind: i64, payload: *mut u8, out: *mut u8) -> i64;

/// The compiler's view thunk, the reverse of [`Ctor`]: `view(value, sink, walk)` writes `value`'s
/// case itself. A scalar goes to the sink's own natives (`sink` is the object they take); a list
/// or a `String`-keyed map goes to [`Walk::array`] or [`Walk::object`] on `walk`.
pub type View = unsafe extern "C-unwind" fn(value: *const u8, sink: *mut u8, walk: *mut u8);

/// The view thunk, as a native argument.
pub struct TreeView(View);

impl AbiType for TreeView {
    type Raw = View;
}
// SAFETY: the compiler passes a thunk with the [`View`] signature.
unsafe impl FromAbi<'_> for TreeView {
    unsafe fn from_raw(raw: View) -> TreeView {
        TreeView(raw)
    }
}

/// A value of the alternative in memory, as a native argument.
pub struct ValueRef<'a>(*const u8, PhantomData<&'a u8>);

impl AbiType for ValueRef<'_> {
    type Raw = *const u8;
}
// SAFETY: the caller passes the address of one live value of the alternative.
unsafe impl<'a> FromAbi<'a> for ValueRef<'a> {
    unsafe fn from_raw(raw: *const u8) -> ValueRef<'a> {
        ValueRef(raw, PhantomData)
    }
}

/// Receives the container events of a tree walk, in document order: an `item` before each array
/// element, a `key` before each member value. Scalars reach the sink through the view thunk.
pub trait TreeSink {
    fn item(&mut self);
    fn key(&mut self, name: &str);
    fn begin_array(&mut self);
    fn end_array(&mut self);
    fn begin_object(&mut self);
    fn end_object(&mut self);
}

/// An open container of a walk.
enum Open {
    Array { at: *const u8, left: usize },
    Object { slots: *const u8, left: usize },
}

/// One tree walk: the open containers and the layout of the alternative. The walk is iterative,
/// so nesting depth costs heap and not stack.
pub struct Walk<S: TreeSink> {
    sink: *mut S,
    size: usize,
    l: Layout,
    open: Vec<Open>,
}

impl<S: TreeSink> Walk<S> {
    fn run(
        sink: &mut S,
        sink_obj: *mut u8,
        desc: ValueDesc<'_>,
        view: TreeView,
        root: ValueRef<'_>,
    ) {
        let desc = desc.0;
        let mut walk = Walk {
            sink,
            size: desc.size as usize,
            l: map::string_map_layout(desc),
            open: Vec::new(),
        };
        let view = view.0;
        let mut value = root.0;
        loop {
            // SAFETY: `value` is a live value of the alternative.
            unsafe { view(value, sink_obj, (&raw mut walk).cast()) };
            // The next value to visit: the following element of the innermost open container,
            // closing the ones that are done.
            loop {
                // SAFETY: `sink` outlives the walk; the thunk's natives that reach it have returned.
                let sink = unsafe { &mut *walk.sink };
                let Some(top) = walk.open.last_mut() else {
                    return;
                };
                match top {
                    Open::Array { at, left } => {
                        if *left == 0 {
                            sink.end_array();
                            walk.open.pop();
                            continue;
                        }
                        sink.item();
                        value = *at;
                        // SAFETY: `left` elements of `size` bytes remain in the list.
                        *at = unsafe { at.add(walk.size) };
                        *left -= 1;
                        break;
                    }
                    Open::Object { slots, left } => {
                        let mut found = None;
                        while *left > 0 {
                            let slot = *slots;
                            // SAFETY: `left` slots of `stride` bytes remain in the map's storage.
                            unsafe {
                                *slots = slot.add(walk.l.stride);
                                *left -= 1;
                                if *slot.cast::<u64>() & LIVE != 0 {
                                    found = Some(slot);
                                    break;
                                }
                            }
                        }
                        let Some(slot) = found else {
                            sink.end_object();
                            walk.open.pop();
                            continue;
                        };
                        // SAFETY: a live slot holds a `String` key and a value at the layout's offsets.
                        unsafe {
                            let key = &*slot.add(walk.l.koff).cast::<StrVal>();
                            sink.key(core::str::from_utf8_unchecked(core::slice::from_raw_parts(
                                key.data(),
                                key.len(),
                            )));
                            value = slot.add(walk.l.voff);
                        }
                        break;
                    }
                }
            }
        }
    }

    /// Opens the array `v`; its elements are visited next.
    pub fn array(&mut self, v: &VecVal) {
        // SAFETY: `sink` outlives the walk and is only used on this thread.
        unsafe { (*self.sink).begin_array() };
        self.open.push(Open::Array {
            at: v.ptr,
            left: v.len,
        });
    }

    /// Opens the object `m`; its members are visited next.
    pub fn object(&mut self, m: &ms_rt_abi::MapVal) {
        // SAFETY: as for [`Walk::array`].
        unsafe { (*self.sink).begin_object() };
        self.open.push(Open::Object {
            slots: m.slots,
            left: m.used,
        });
    }
}

/// The runtime object a walk feeds, as a native argument: the object the view thunk's scalar
/// natives take, whose value is the [`TreeSink`].
pub struct SinkObj<'a, T: AbiHandle + TreeSink>(*mut ObjCell<T>, PhantomData<&'a mut T>);

impl<T: AbiHandle + TreeSink> SinkObj<'_, T> {
    /// Walks `root`, a value of the alternative described by `desc` read through `view`, writing
    /// it to the sink.
    pub fn walk(self, desc: ValueDesc<'_>, view: TreeView, root: ValueRef<'_>) {
        // SAFETY: the object is live and unaliased for the call; the thunk and root come from
        // the compiler for one alternative.
        let ObjMut(sink) = unsafe { ObjMut::<T>::from_raw(self.0) };
        Walk::run(sink, self.0.cast(), desc, view, root);
    }
}

impl<T: AbiHandle + TreeSink> AbiType for SinkObj<'_, T> {
    type Raw = *mut ObjCell<T>;
}
// SAFETY: an object argument is a live runtime object that outlives the call and is not aliased.
unsafe impl<'a, T: AbiHandle + TreeSink> FromAbi<'a> for SinkObj<'a, T> {
    unsafe fn from_raw(raw: *mut ObjCell<T>) -> SinkObj<'a, T> {
        SinkObj(raw, PhantomData)
    }
}

/// A walk, as a native argument for the thunk's container natives.
pub struct WalkRef<'a, S: TreeSink>(pub &'a mut Walk<S>);

impl<S: TreeSink> AbiType for WalkRef<'_, S> {
    type Raw = *mut Walk<S>;
}
// SAFETY: the view thunk passes the walk pointer it was given.
unsafe impl<'a, S: TreeSink> FromAbi<'a> for WalkRef<'a, S> {
    unsafe fn from_raw(raw: *mut Walk<S>) -> WalkRef<'a, S> {
        // SAFETY: caller contract.
        WalkRef(unsafe { &mut *raw })
    }
}

/// A list in memory, as a native argument.
pub struct ListRef<'a>(pub &'a VecVal);

impl AbiType for ListRef<'_> {
    type Raw = *const VecVal;
}
// SAFETY: the compiler passes the address of a live list.
unsafe impl<'a> FromAbi<'a> for ListRef<'a> {
    unsafe fn from_raw(raw: *const VecVal) -> ListRef<'a> {
        // SAFETY: caller contract.
        ListRef(unsafe { &*raw })
    }
}

/// A map in memory, as a native argument.
pub struct MapRef<'a>(pub &'a ms_rt_abi::MapVal);

impl AbiType for MapRef<'_> {
    type Raw = *const ms_rt_abi::MapVal;
}
// SAFETY: the compiler passes the address of a live map.
unsafe impl<'a> FromAbi<'a> for MapRef<'a> {
    unsafe fn from_raw(raw: *const ms_rt_abi::MapVal) -> MapRef<'a> {
        // SAFETY: caller contract.
        MapRef(unsafe { &*raw })
    }
}

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
