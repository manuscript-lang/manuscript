//! Growable buffers over the runtime allocator.
use crate::alloc;
use core::fmt;
use core::ptr::null_mut;

/// Growable byte buffer; frees on drop.
pub struct ByteBuf {
    ptr: *mut u8,
    len: usize,
    cap: usize,
}

impl ByteBuf {
    pub const fn new() -> Self {
        ByteBuf { ptr: null_mut(), len: 0, cap: 0 }
    }

    pub fn with_capacity(cap: usize) -> Self {
        let mut b = Self::new();
        b.reserve(cap);
        b
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn reserve(&mut self, extra: usize) {
        let need = self.len.checked_add(extra).unwrap_or_else(|| crate::fault::fatal(b"out of memory"));
        if need <= self.cap {
            return;
        }
        let cap = need.max(self.cap * 2).max(32);
        // SAFETY: `ptr` is null or a live block from the runtime allocator.
        self.ptr = unsafe { alloc::realloc(self.ptr, cap) };
        self.cap = cap;
    }

    #[inline]
    pub fn push(&mut self, b: u8) {
        if self.len == self.cap {
            self.reserve(1);
        }
        // SAFETY: capacity was ensured above.
        unsafe { *self.ptr.add(self.len) = b };
        self.len += 1;
    }

    #[inline]
    pub fn extend(&mut self, data: &[u8]) {
        self.reserve(data.len());
        // SAFETY: capacity reserved; `data` cannot alias our private buffer.
        unsafe { core::ptr::copy_nonoverlapping(data.as_ptr(), self.ptr.add(self.len), data.len()) };
        self.len += data.len();
    }

    pub fn push_i64(&mut self, v: i64) {
        let mut tmp = [0u8; 20];
        self.extend(crate::num::format_i64(v, &mut tmp));
    }

    pub fn push_char(&mut self, c: u32) {
        let mut tmp = [0u8; 4];
        let n = crate::utf8::encode(c, &mut tmp);
        self.extend(&tmp[..n]);
    }

    pub fn clear(&mut self) {
        self.len = 0;
    }

    pub fn as_slice(&self) -> &[u8] {
        if self.ptr.is_null() {
            return &[];
        }
        // SAFETY: `ptr` holds `len` initialised bytes.
        unsafe { core::slice::from_raw_parts(self.ptr, self.len) }
    }

    /// Truncates to `len` bytes.
    pub fn truncate(&mut self, len: usize) {
        self.len = self.len.min(len);
    }

    /// Takes the raw parts, leaving the buffer empty.
    pub fn into_raw(mut self) -> (*mut u8, usize, usize) {
        let r = (self.ptr, self.len, self.cap);
        self.ptr = null_mut();
        self.len = 0;
        self.cap = 0;
        r
    }
}

impl Default for ByteBuf {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for ByteBuf {
    fn drop(&mut self) {
        // SAFETY: `ptr` is null or a live runtime block owned by this buffer.
        unsafe { alloc::free(self.ptr) };
    }
}

impl fmt::Write for ByteBuf {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.extend(s.as_bytes());
        Ok(())
    }
}

/// Growable vector of `Copy` items.
pub struct RawVec<T: Copy> {
    ptr: *mut T,
    len: usize,
    cap: usize,
}

impl<T: Copy> RawVec<T> {
    pub const fn new() -> Self {
        RawVec { ptr: null_mut(), len: 0, cap: 0 }
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn push(&mut self, v: T) {
        if self.len == self.cap {
            let cap = (self.cap * 2).max(8);
            // SAFETY: `ptr` is null or a live runtime block.
            self.ptr = unsafe { alloc::realloc(self.ptr.cast(), cap * size_of::<T>()) }.cast();
            self.cap = cap;
        }
        // SAFETY: capacity ensured above.
        unsafe { self.ptr.add(self.len).write(v) };
        self.len += 1;
    }

    pub fn pop(&mut self) -> Option<T> {
        if self.len == 0 {
            return None;
        }
        self.len -= 1;
        // SAFETY: element `len` was initialised.
        Some(unsafe { self.ptr.add(self.len).read() })
    }

    pub fn get(&self, i: usize) -> T {
        assert!(i < self.len);
        // SAFETY: bounds checked.
        unsafe { self.ptr.add(i).read() }
    }

    pub fn clear(&mut self) {
        self.len = 0;
    }

    pub fn as_slice(&self) -> &[T] {
        if self.ptr.is_null() {
            return &[];
        }
        // SAFETY: `len` initialised elements.
        unsafe { core::slice::from_raw_parts(self.ptr, self.len) }
    }
}

impl<T: Copy> Drop for RawVec<T> {
    fn drop(&mut self) {
        // SAFETY: owned runtime block or null.
        unsafe { alloc::free(self.ptr.cast()) };
    }
}
