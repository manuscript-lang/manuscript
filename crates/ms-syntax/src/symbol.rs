//! Interned identifiers.
//!
//! A [`Symbol`] is a `u32` index into an [`Interner`]. Equality and hashing compare the integer;
//! text, display and text order go through a [`Names`] handle. An interner owns its names and frees
//! them when dropped. A [`Session`] owns one for a long-lived process (the language server) and
//! frees it with [`Session::release`]; every other process uses the process-wide default and never
//! frees it. See `proposals/session-owned-interner.md`.
#![allow(unsafe_code)]

use std::cell::Cell;
use std::cmp::Ordering;
use std::fmt;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicU64, Ordering as Atomic};
use std::sync::{Mutex, OnceLock};

/// An interned string: an index into one [`Interner`], meaningful only with the [`Names`] that
/// made it. Orders by intern order, which is deterministic but not alphabetical; use
/// [`Names::cmp`] when output must be sorted by text.
#[derive(Copy, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Symbol(u32);

impl fmt::Debug for Symbol {
    /// Text when the symbol belongs to the current interner, else its index.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match Names::global().try_str(*self) {
            Some(text) => write!(f, "{text:?}"),
            None => write!(f, "#{}", self.0),
        }
    }
}

/// The handle through which names are interned and read. It is `Copy` and points at one
/// [`Interner`]; pass it down and store it with the structure that owns the symbols.
#[derive(Copy, Clone)]
pub struct Names(&'static Interner);

impl Default for Names {
    fn default() -> Names {
        Names::global()
    }
}

impl fmt::Debug for Names {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Names")
    }
}

thread_local! {
    static CURRENT: Cell<Option<Names>> = const { Cell::new(None) };
}

impl Names {
    /// The interner of the session entered on this thread, else the process default. For code
    /// that has no handle to take (tests, tools, `n(..)` helpers); give new code a parameter.
    pub fn global() -> Names {
        if let Some(names) = CURRENT.with(Cell::get) {
            return names;
        }
        static DEFAULT: OnceLock<Interner> = OnceLock::new();
        Names(DEFAULT.get_or_init(Interner::new))
    }

    /// Interns `text`.
    pub fn intern(self, text: &str) -> Symbol {
        self.0.intern(text)
    }

    /// The text of `sym`. The text lives as long as the interner: forever for the process default,
    /// until [`Session::release`] for a session.
    pub fn str<'a>(self, sym: impl std::borrow::Borrow<Symbol>) -> &'a str {
        self.try_str(*sym.borrow())
            .unwrap_or_else(|| panic!("symbol #{} is not in this interner", sym.borrow().0))
    }

    /// The text of `sym`, or `None` when its index is out of range for this interner.
    pub fn try_str<'a>(self, sym: Symbol) -> Option<&'a str> {
        self.0.get(sym.0)
    }

    /// Bytes of text this interner holds.
    pub fn text_bytes(self) -> usize {
        self.0.text_bytes()
    }

    /// Distinguishes this interner from every other made in the process, including freed ones.
    /// Caches keyed by symbols compare it to notice a session change.
    pub fn generation(self) -> u64 {
        self.0.generation
    }

    /// Orders two symbols by text, so sorted output is deterministic and alphabetical.
    pub fn cmp(self, a: Symbol, b: Symbol) -> Ordering {
        self.str(a).cmp(self.str(b))
    }
}

/// A string table that owns its names. Id 0 is the empty string.
pub struct Interner {
    generation: u64,
    state: Mutex<State>,
}

struct State {
    /// Owned allocations from `Box::leak`, freed by `Interner::drop`. Index 0 is a placeholder.
    texts: Vec<Text>,
    /// Open-addressed ids, 0 for empty; the length is a power of two and at least twice `texts`.
    slots: Vec<u32>,
    /// Total length of the texts.
    bytes: usize,
}

#[derive(Copy, Clone)]
struct Text(NonNull<str>);

// SAFETY: a `Text` owns an immutable heap string that only `Interner::drop` frees.
unsafe impl Send for Text {}

fn hash_text(text: &str) -> u32 {
    // FNV-1a, folded to 32 bits.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in text.bytes() {
        h = (h ^ u64::from(b)).wrapping_mul(0x100_0000_01b3);
    }
    (h ^ (h >> 32)) as u32
}

impl Default for Interner {
    fn default() -> Self {
        Self::new()
    }
}

impl Interner {
    /// An interner holding only the empty string.
    pub fn new() -> Interner {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        Interner {
            generation: NEXT.fetch_add(1, Atomic::Relaxed),
            state: Mutex::new(State {
                texts: vec![Text(NonNull::from(""))],
                slots: vec![0; 4096],
                bytes: 0,
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The number of interned strings, counting the empty string.
    pub fn len(&self) -> usize {
        self.lock().texts.len()
    }

    /// Always false: the empty string is interned from the start.
    pub fn is_empty(&self) -> bool {
        false
    }

    /// Bytes of text held.
    pub fn text_bytes(&self) -> usize {
        self.lock().bytes
    }

    fn get<'a>(&self, id: u32) -> Option<&'a str> {
        let text = *self.lock().texts.get(id as usize)?;
        // SAFETY: the allocation is never moved or mutated, and is freed only when the interner is
        // dropped (`Interner::drop`) or released (`Session::release`), which require that no text
        // borrowed from it is still in use. The lifetime is chosen by the caller for that reason.
        Some(unsafe { &*text.0.as_ptr() })
    }

    /// Interns `text`.
    pub fn intern(&self, text: &str) -> Symbol {
        if text.is_empty() {
            return Symbol(0);
        }
        let mut state = self.lock();
        let mask = state.slots.len() - 1;
        let mut at = hash_text(text) as usize & mask;
        loop {
            let id = state.slots[at];
            if id == 0 {
                break;
            }
            // SAFETY: every `Text` points at a live allocation owned by this interner.
            if unsafe { state.texts[id as usize].0.as_ref() } == text {
                return Symbol(id);
            }
            at = (at + 1) & mask;
        }
        let id = state.texts.len() as u32;
        let leaked: &'static mut str = Box::leak(text.to_owned().into_boxed_str());
        state.bytes += text.len();
        state.texts.push(Text(NonNull::from(leaked)));
        state.slots[at] = id;
        if state.texts.len() * 2 > state.slots.len() {
            state.grow();
        }
        Symbol(id)
    }
}

impl State {
    fn grow(&mut self) {
        let mut slots = vec![0u32; self.slots.len() * 2];
        let mask = slots.len() - 1;
        for id in 1..self.texts.len() as u32 {
            // SAFETY: every `Text` points at a live allocation owned by this interner.
            let text = unsafe { self.texts[id as usize].0.as_ref() };
            let mut at = hash_text(text) as usize & mask;
            while slots[at] != 0 {
                at = (at + 1) & mask;
            }
            slots[at] = id;
        }
        self.slots = slots;
    }
}

impl Drop for Interner {
    fn drop(&mut self) {
        let state = self.state.get_mut().unwrap_or_else(|e| e.into_inner());
        for text in state.texts.drain(1..) {
            // SAFETY: allocated by `Box::leak` in `intern`, freed once here, and `&mut self`
            // means no `get` borrow is alive.
            drop(unsafe { Box::from_raw(text.0.as_ptr()) });
        }
    }
}

/// An interner that belongs to a long-lived unit of work (an editor workspace) and can be freed
/// when that work ends. Dropping a `Session` leaks its names, which is always safe; freeing them
/// is [`Session::release`].
pub struct Session {
    interner: NonNull<Interner>,
}

// SAFETY: the interner it points at is `Sync` and owned by the session.
unsafe impl Send for Session {}

impl Session {
    /// A new, empty session.
    pub fn new() -> Session {
        Session {
            interner: NonNull::from(Box::leak(Box::new(Interner::new()))),
        }
    }

    /// The handle for this session's names.
    pub fn names(&self) -> Names {
        // SAFETY: the interner is live until `release`, which consumes the session; the `'static`
        // lifetime is the contract `release` imposes on every handle.
        Names(unsafe { self.interner.as_ref() })
    }

    /// Makes the names of this session current on this thread until the guard drops, so `n(..)`
    /// and [`Names::global`] reach it.
    pub fn enter(&self) -> Entered {
        let names = self.names();
        Entered(CURRENT.with(|c| c.replace(Some(names))))
    }

    /// Frees every name in the session.
    ///
    /// # Safety
    ///
    /// No [`Names`] handle, [`Symbol`], or `&str` obtained from this session may be used afterward:
    /// not by a structure that still holds one, and not on another thread.
    pub unsafe fn release(self) {
        // SAFETY: allocated by `Box::leak` in `new`, freed once because `self` is consumed; the
        // caller guarantees nothing borrowed from it remains.
        drop(unsafe { Box::from_raw(self.interner.as_ptr()) });
    }
}

impl Default for Session {
    fn default() -> Self {
        Session::new()
    }
}

/// Restores the previously current interner when dropped.
pub struct Entered(Option<Names>);

impl Drop for Entered {
    fn drop(&mut self) {
        CURRENT.with(|c| c.set(self.0));
    }
}

#[cfg(test)]
mod interner_tests {
    use super::*;

    #[test]
    fn equal_text_shares_an_id_and_round_trips() {
        let t = Session::new();
        let names = t.names();
        let a = names.intern("alpha");
        let b = names.intern("beta");
        assert_ne!(a, b);
        assert_eq!(names.intern("alpha"), a);
        assert_eq!((names.str(a), names.str(b)), ("alpha", "beta"));
        assert_eq!(names.intern(""), Symbol(0));
        assert_eq!(names.str(Symbol(0)), "");
        assert_eq!(names.cmp(b, a), Ordering::Greater);
        assert_eq!(names.text_bytes(), "alphabeta".len());
        assert_ne!(names.generation(), Names::global().generation());
        // SAFETY: nothing borrowed from the session is used afterward.
        unsafe { t.release() };
    }

    #[test]
    fn survives_growth() {
        let i = Interner::new();
        let names = Names(Box::leak(Box::new(Interner::new())));
        let ids: Vec<Symbol> = (0..9000)
            .map(|k| names.intern(&format!("name{k}")))
            .collect();
        for (k, id) in ids.iter().enumerate() {
            assert_eq!(names.str(*id), format!("name{k}"));
            assert_eq!(names.intern(&format!("name{k}")), *id);
        }
        assert_eq!(names.0.len(), 9001);
        assert_eq!(i.len(), 1);
    }

    #[test]
    fn sessions_are_independent_and_enter_restores() {
        let a = Session::new();
        let b = Session::new();
        let before = Names::global().intern("outside");
        {
            let _in = a.enter();
            let x = Names::global().intern("x");
            assert_eq!(a.names().str(x), "x");
            assert_eq!(b.names().intern("y"), Symbol(1));
        }
        assert_eq!(Names::global().str(before), "outside");
        // SAFETY: nothing borrowed from either session is used afterward.
        unsafe {
            a.release();
            b.release();
        }
    }
}
