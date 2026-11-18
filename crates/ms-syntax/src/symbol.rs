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
use std::sync::atomic::{AtomicPtr, AtomicU32, AtomicU64, Ordering as Atomic};
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
///
/// Reading a name takes no lock: the texts sit in append-only segments that never move, so a
/// symbol resolves with one atomic load and one index. Only interning takes the mutex.
pub struct Interner {
    generation: u64,
    /// Count of published texts, including the empty string. A text is written before this grows
    /// past its id, so every id below it can be read.
    len: AtomicU32,
    /// Segment `k` holds `FIRST << k` texts and is allocated once, on first use, never freed
    /// before the interner drops.
    segments: [AtomicPtr<Text>; SEGMENTS],
    /// The hash table lookups probe without the lock; it points into a box that `state` owns.
    table: AtomicPtr<Table>,
    state: Mutex<State>,
}

/// Texts in segment 0.
const FIRST: usize = 1024;
/// Enough segments to hold every `u32` id.
const SEGMENTS: usize = 22;

/// Open-addressed ids, 0 for empty; the length is a power of two and at least twice the texts.
/// A slot is written once, after its text is published, so a reader that sees an id can read it.
struct Table {
    mask: usize,
    slots: Box<[AtomicU32]>,
}

impl Table {
    fn new(len: usize) -> Box<Table> {
        Box::new(Table {
            mask: len - 1,
            slots: (0..len).map(|_| AtomicU32::new(0)).collect(),
        })
    }
}

struct State {
    /// Every table the interner has had, the current one last. A table that growth replaced stays
    /// alive until the interner drops, because a lookup may still be probing it.
    // Boxed so a table keeps its address while the vector grows; `Interner::table` points at it.
    #[allow(clippy::vec_box)]
    tables: Vec<Box<Table>>,
    /// Total length of the texts.
    bytes: usize,
}

#[derive(Copy, Clone)]
struct Text(NonNull<str>);

// SAFETY: a `Text` owns an immutable heap string that only `Interner::drop` frees.
unsafe impl Send for Text {}
// SAFETY: the same immutable string, read from many threads.
unsafe impl Sync for Text {}

/// The segment holding `id` and its offset in it.
fn locate(id: usize) -> (usize, usize) {
    let block = id / FIRST + 1;
    let segment = (usize::BITS - 1 - block.leading_zeros()) as usize;
    (segment, id - FIRST * ((1 << segment) - 1))
}

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
        let interner = Interner {
            generation: NEXT.fetch_add(1, Atomic::Relaxed),
            len: AtomicU32::new(0),
            segments: std::array::from_fn(|_| AtomicPtr::new(std::ptr::null_mut())),
            table: AtomicPtr::new(std::ptr::null_mut()),
            state: Mutex::new(State {
                tables: Vec::new(),
                bytes: 0,
            }),
        };
        {
            let mut state = interner.lock();
            interner.install(&mut state, Table::new(4096));
        }
        interner.push(Text(NonNull::from("")));
        interner
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Appends a text and publishes it. Called with the state lock held (or before sharing).
    fn push(&self, text: Text) -> u32 {
        let id = self.len.load(Atomic::Relaxed);
        let (segment, offset) = locate(id as usize);
        let mut base = self.segments[segment].load(Atomic::Acquire);
        if base.is_null() {
            let block: Box<[Text]> = vec![Text(NonNull::from("")); FIRST << segment].into();
            base = Box::into_raw(block).cast::<Text>();
            self.segments[segment].store(base, Atomic::Release);
        }
        // SAFETY: `offset` is inside the segment, and no reader looks at it before `len` passes it.
        unsafe { base.add(offset).write(text) };
        self.len.store(id + 1, Atomic::Release);
        id
    }

    /// The number of interned strings, counting the empty string.
    pub fn len(&self) -> usize {
        self.len.load(Atomic::Acquire) as usize
    }

    /// Always false: the empty string is interned from the start.
    pub fn is_empty(&self) -> bool {
        false
    }

    /// Bytes of text held.
    pub fn text_bytes(&self) -> usize {
        self.lock().bytes
    }

    fn text(&self, id: u32) -> Text {
        let (segment, offset) = locate(id as usize);
        let base = self.segments[segment].load(Atomic::Acquire);
        // SAFETY: the caller checked `id < len`, so the segment exists and the text is written.
        unsafe { *base.add(offset) }
    }

    fn get<'a>(&self, id: u32) -> Option<&'a str> {
        if id >= self.len.load(Atomic::Acquire) {
            return None;
        }
        // SAFETY: the allocation is never moved or mutated, and is freed only when the interner is
        // dropped (`Interner::drop`) or released (`Session::release`), which require that no text
        // borrowed from it is still in use. The lifetime is chosen by the caller for that reason.
        Some(unsafe { &*self.text(id).0.as_ptr() })
    }

    /// Makes `table` the one lookups probe.
    fn install(&self, state: &mut State, table: Box<Table>) {
        self.table
            .store(std::ptr::from_ref(&*table).cast_mut(), Atomic::Release);
        state.tables.push(table);
    }

    /// The id of `text` in `table`, or the empty slot where it belongs.
    fn probe(&self, table: &Table, text: &str, hash: usize) -> Result<Symbol, usize> {
        let mut at = hash & table.mask;
        loop {
            let id = table.slots[at].load(Atomic::Acquire);
            if id == 0 {
                return Err(at);
            }
            // SAFETY: a slot holds an id only after its text was published (`push`, then the
            // slot's release store), and every `Text` points at a live allocation of this interner.
            if unsafe { self.text(id).0.as_ref() } == text {
                return Ok(Symbol(id));
            }
            at = (at + 1) & table.mask;
        }
    }

    /// Interns `text`. A name already interned is found without the lock, so threads that read
    /// the same names do not queue behind each other.
    pub fn intern(&self, text: &str) -> Symbol {
        if text.is_empty() {
            return Symbol(0);
        }
        let hash = hash_text(text) as usize;
        // SAFETY: the pointer is to a box `state` keeps until the interner drops.
        let table = unsafe { &*self.table.load(Atomic::Acquire) };
        if let Ok(found) = self.probe(table, text, hash) {
            return found;
        }
        let mut state = self.lock();
        // A table installed since the lock-free probe, or a text another thread just added.
        let table: &Table = state.tables.last().expect("a table is installed");
        // SAFETY: the box lives as long as `state`, which only grows; the borrow of `state`
        // ends here so `grow` can take it again.
        let table: &Table = unsafe { &*std::ptr::from_ref(table) };
        let at = match self.probe(table, text, hash) {
            Ok(found) => return found,
            Err(at) => at,
        };
        let leaked: &'static mut str = Box::leak(text.to_owned().into_boxed_str());
        state.bytes += text.len();
        let id = self.push(Text(NonNull::from(leaked)));
        table.slots[at].store(id, Atomic::Release);
        if self.len() * 2 > table.slots.len() {
            self.grow(&mut state);
        }
        Symbol(id)
    }

    fn grow(&self, state: &mut State) {
        let table = Table::new(state.tables.last().map_or(4096, |t| t.slots.len()) * 2);
        for id in 1..self.len() as u32 {
            // SAFETY: every `Text` points at a live allocation owned by this interner.
            let text = unsafe { self.text(id).0.as_ref() };
            let mut at = hash_text(text) as usize & table.mask;
            while table.slots[at].load(Atomic::Relaxed) != 0 {
                at = (at + 1) & table.mask;
            }
            table.slots[at].store(id, Atomic::Relaxed);
        }
        self.install(state, table);
    }
}

impl Drop for Interner {
    fn drop(&mut self) {
        let len = *self.len.get_mut() as usize;
        for id in 1..len {
            // SAFETY: allocated by `Box::leak` in `intern`, freed once here, and `&mut self`
            // means no `get` borrow is alive.
            drop(unsafe { Box::from_raw(self.text(id as u32).0.as_ptr()) });
        }
        for (segment, base) in self.segments.iter_mut().enumerate() {
            let base = *base.get_mut();
            if !base.is_null() {
                // SAFETY: allocated in `push` as a boxed slice of this length, freed once here.
                drop(unsafe {
                    Box::from_raw(std::ptr::slice_from_raw_parts_mut(base, FIRST << segment))
                });
            }
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
    fn threads_read_while_others_intern() {
        let names = Names(Box::leak(Box::new(Interner::new())));
        std::thread::scope(|scope| {
            for thread in 0..4 {
                scope.spawn(move || {
                    for k in 0..5000 {
                        let text = format!("t{thread}-{k}");
                        let id = names.intern(&text);
                        assert_eq!(names.str(id), text);
                    }
                });
            }
        });
        assert_eq!(names.0.len(), 20001);
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
