//! `FileWatcher`: a polling watcher (snapshot comparison) and a native one (inotify on Linux,
//! kqueue on macOS, `ReadDirectoryChangesW` on Windows).
//! Both are driven from `next`, which waits in short slices and polls
//! for cancellation between them, so no worker thread is needed.
use crate::err::{Fail, Res};
use crate::path;
use crate::sys::{self, CPath};
use alloc::collections::BTreeMap;
#[cfg(target_os = "linux")]
use alloc::collections::VecDeque;
use alloc::vec::Vec;
use core::sync::atomic::{AtomicBool, Ordering};
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{STATUS_CLOSED, STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};

const SLICE_MS: i32 = 50;

/// One event: the affected path and whether it appeared/disappeared/moved (`rename`) or changed.
pub struct Event {
    pub path: Vec<u8>,
    pub rename: bool,
}

type Stamp = (u32, i64, i64, i64);

fn stamp(st: &sys::Stat) -> Stamp {
    (st.mode, st.size, st.modified.0, st.modified.1)
}

fn snapshot(root: &[u8], recursive: bool, max: i64) -> Res<BTreeMap<Vec<u8>, Stamp>> {
    let mut out = BTreeMap::new();
    visit(root, root, recursive, max, &mut out)?;
    Ok(out)
}

fn visit(
    root: &[u8],
    p: &[u8],
    recursive: bool,
    max: i64,
    out: &mut BTreeMap<Vec<u8>, Stamp>,
) -> Res<()> {
    poll_cancel();
    if out.len() as i64 >= max {
        return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
    }
    if core::str::from_utf8(p).is_err() {
        return Err(Fail::status(STATUS_UNSUPPORTED));
    }
    let c = CPath::new(p).ok_or_else(Fail::invalid)?;
    let st = sys::stat(&c, false).map_err(|e| Fail::errno(e, "lstat", p))?;
    out.insert(p.to_vec(), stamp(&st));
    if !sys::is_dir(&st) || (p != root && !recursive) {
        return Ok(());
    }
    let mut entries = sys::read_dir(&c).map_err(|e| Fail::errno(e, "open", p))?;
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, _) in entries {
        visit(root, &path::join(p, &name), recursive, max, out)?;
    }
    Ok(())
}

/// Waits for inotify events: the task parks, so other tasks keep running.
#[cfg(target_os = "linux")]
fn wait_events(fd: sys::Fd) {
    #[cfg(not(test))]
    ms_rt::glue::task_wait_fd(fd, ms_rt::glue::WAIT_READ, i64::from(SLICE_MS) * 1_000_000);
    // Tests run on many threads, which the runtime's scheduler does not support.
    #[cfg(test)]
    sys::wait_ready(fd, sys::Interest::Read, SLICE_MS);
}

/// What differs between two snapshots, sorted by path: `rename` for an entry that appeared or
/// disappeared, otherwise a change.
fn diff(before: &BTreeMap<Vec<u8>, Stamp>, now: &BTreeMap<Vec<u8>, Stamp>) -> Vec<Event> {
    let mut changes: BTreeMap<&Vec<u8>, bool> = BTreeMap::new();
    for (p, s) in now {
        match before.get(p) {
            None => {
                changes.insert(p, true);
            }
            Some(old) if old != s => {
                changes.insert(p, false);
            }
            _ => {}
        }
    }
    for p in before.keys() {
        if !now.contains_key(p) {
            changes.insert(p, true);
        }
    }
    changes
        .into_iter()
        .map(|(p, rename)| Event {
            path: p.clone(),
            rename,
        })
        .collect()
}

/// The arguments every native watcher accepts: `max` bounds the paths under the root (the root,
/// files and directories) counted once at start, as for the polling watcher, on every platform;
/// `events` bounds queued events and `overflow` is `error` or `ignore`.
fn valid_native(root: &[u8], recursive: bool, max: i64, events: i64, overflow: &[u8]) -> Res<()> {
    if root.is_empty()
        || max <= 0
        || events <= 0
        || events > 1_048_576
        || (overflow != b"error" && overflow != b"ignore")
    {
        return Err(Fail::invalid());
    }
    snapshot(root, recursive, max).map(drop)
}

fn sleep_slice() {
    #[cfg(not(test))]
    ms_rt::glue::task_sleep(i64::from(SLICE_MS) * 1_000_000);
    #[cfg(test)]
    sys::sleep_ms(SLICE_MS);
}

pub struct Poll {
    root: Vec<u8>,
    recursive: bool,
    interval_ns: i64,
    max: i64,
    before: BTreeMap<Vec<u8>, Stamp>,
}

impl Poll {
    pub fn new(root: &[u8], recursive: bool, interval_ns: i64, max: i64) -> Res<Poll> {
        if interval_ns <= 0 || max < 0 || root.is_empty() {
            return Err(Fail::invalid());
        }
        let before = snapshot(root, recursive, max)?;
        Ok(Poll {
            root: root.to_vec(),
            recursive,
            interval_ns,
            max,
            before,
        })
    }

    /// Every difference seen after one interval, sorted by path; waits until there is one.
    fn next(&mut self, closed: &AtomicBool) -> Res<Vec<Event>> {
        loop {
            let mut waited = 0i64;
            while waited < self.interval_ns {
                poll_cancel();
                if closed.load(Ordering::Relaxed) {
                    return Err(Fail::status(STATUS_CLOSED));
                }
                sleep_slice();
                waited += i64::from(SLICE_MS) * 1_000_000;
            }
            let now = match snapshot(&self.root, self.recursive, self.max) {
                Ok(s) => s,
                Err(f) if f.status == ms_rt_abi::STATUS_NOT_FOUND => BTreeMap::new(),
                Err(f) => return Err(f),
            };
            let events = diff(&self.before, &now);
            self.before = now;
            if !events.is_empty() {
                return Ok(events);
            }
        }
    }
}

#[cfg(target_os = "linux")]
pub struct Native {
    fd: i32,
    recursive: bool,
    ignore_overflow: bool,
    capacity: usize,
    watches: BTreeMap<i32, Vec<u8>>,
    queue: VecDeque<Event>,
    terminal: Option<Fail>,
}

#[cfg(target_os = "linux")]
const MASK: u32 = (libc::IN_MOVED_TO
    | libc::IN_MOVED_FROM
    | libc::IN_CREATE
    | libc::IN_ATTRIB
    | libc::IN_MODIFY
    | libc::IN_MOVE_SELF
    | libc::IN_DELETE
    | libc::IN_DELETE_SELF) as u32;

#[cfg(target_os = "linux")]
impl Native {
    /// `overflow` is `error` or `ignore`; `max` bounds the paths under the root, `events` queued events.
    pub fn new(
        root: &[u8],
        recursive: bool,
        max: i64,
        events: i64,
        overflow: &[u8],
    ) -> Res<Native> {
        valid_native(root, recursive, max, events, overflow)?;
        // SAFETY: plain system call.
        let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC | libc::IN_NONBLOCK) };
        if fd < 0 {
            return Err(Fail::raw(sys::errno()));
        }
        let mut n = Native {
            fd,
            recursive,
            ignore_overflow: overflow == b"ignore",
            capacity: events as usize,
            watches: BTreeMap::new(),
            queue: VecDeque::new(),
            terminal: None,
        };
        n.add_tree(root)?;
        Ok(n)
    }

    fn add_tree(&mut self, root: &[u8]) -> Res<()> {
        self.add_dir(root, root)
    }

    fn add_dir(&mut self, root: &[u8], p: &[u8]) -> Res<()> {
        poll_cancel();
        if core::str::from_utf8(p).is_err() {
            return Err(Fail::status(STATUS_UNSUPPORTED));
        }
        let c = CPath::new(p).ok_or_else(Fail::invalid)?;
        let st = sys::stat(&c, false).map_err(|e| Fail::errno(e, "lstat", p))?;
        if p != root && !sys::is_dir(&st) {
            return Ok(());
        }
        if !self.watches.values().any(|w| w == p) {
            // SAFETY: `c` is a NUL-terminated path and `fd` an inotify descriptor.
            let wd = unsafe { libc::inotify_add_watch(self.fd, c.as_ptr(), MASK) };
            if wd < 0 {
                return Err(Fail::errno(sys::errno(), "inotify_add_watch", p));
            }
            self.watches.insert(wd, p.to_vec());
        }
        if !sys::is_dir(&st) || !self.recursive {
            return Ok(());
        }
        for (name, _) in sys::read_dir(&c).map_err(|e| Fail::errno(e, "open", p))? {
            self.add_dir(root, &path::join(p, &name))?;
        }
        Ok(())
    }

    /// Queues a `rename` event for everything already inside the new directory `dir`.
    fn report_existing(&mut self, dir: &[u8]) {
        let Some(c) = CPath::new(dir) else { return };
        let Ok(entries) = sys::read_dir(&c) else {
            return;
        };
        for (name, _) in entries {
            let child = path::join(dir, &name);
            if core::str::from_utf8(&child).is_err() {
                continue;
            }
            self.push(Event {
                path: child.clone(),
                rename: true,
            });
            if CPath::new(&child)
                .and_then(|c| sys::stat(&c, false).ok())
                .is_some_and(|st| sys::is_dir(&st))
            {
                self.report_existing(&child);
            }
        }
    }

    fn push(&mut self, e: Event) {
        if self.queue.len() >= self.capacity {
            if !self.ignore_overflow && self.terminal.is_none() {
                self.terminal = Some(Fail::status(STATUS_LIMIT_EXCEEDED));
            }
            return;
        }
        self.queue.push_back(e);
    }

    /// Reads and decodes what the kernel has queued.
    fn drain(&mut self) {
        let mut buf = [0u8; 4096];
        loop {
            // SAFETY: `buf` is writable for its length.
            let n = unsafe { libc::read(self.fd, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                return;
            }
            let mut at = 0usize;
            let n = n as usize;
            while at + 16 <= n {
                let wd = i32::from_ne_bytes(buf[at..at + 4].try_into().unwrap());
                let mask = u32::from_ne_bytes(buf[at + 4..at + 8].try_into().unwrap());
                let len = u32::from_ne_bytes(buf[at + 12..at + 16].try_into().unwrap()) as usize;
                let name = &buf[at + 16..(at + 16 + len).min(n)];
                let name = &name[..name.iter().position(|&c| c == 0).unwrap_or(name.len())];
                at += 16 + len;
                self.event(wd, mask, name);
            }
        }
    }

    fn event(&mut self, wd: i32, mask: u32, name: &[u8]) {
        if mask & libc::IN_Q_OVERFLOW as u32 != 0 {
            if !self.ignore_overflow && self.terminal.is_none() {
                self.terminal = Some(Fail::status(STATUS_LIMIT_EXCEEDED));
            }
            return;
        }
        let Some(dir) = self.watches.get(&wd).cloned() else {
            return;
        };
        if mask & libc::IN_IGNORED as u32 != 0 {
            self.watches.remove(&wd);
            return;
        }
        let full = if name.is_empty() {
            dir.clone()
        } else {
            path::join(&dir, name)
        };
        if mask & (libc::IN_DELETE_SELF | libc::IN_MOVE_SELF) as u32 != 0
            || mask & (libc::IN_DELETE | libc::IN_MOVED_FROM) as u32 != 0
        {
            let prefix = {
                let mut p = full.clone();
                p.push(b'/');
                p
            };
            self.watches
                .retain(|_, w| *w != full && !w.starts_with(&prefix));
        }
        let mut fresh = false;
        if self.recursive
            && mask & (libc::IN_CREATE | libc::IN_MOVED_TO) as u32 != 0
            && let Some(c) = CPath::new(&full)
            && sys::stat(&c, false).is_ok_and(|st| sys::is_dir(&st))
        {
            match self.add_tree(&full) {
                Ok(()) => fresh = true,
                Err(f) if f.status == ms_rt_abi::STATUS_NOT_FOUND => {}
                Err(f) => {
                    self.terminal = Some(f);
                    return;
                }
            }
        }
        if core::str::from_utf8(&full).is_err() {
            self.terminal = Some(Fail::status(STATUS_UNSUPPORTED));
            return;
        }
        let rename = mask
            & (libc::IN_CREATE
                | libc::IN_DELETE
                | libc::IN_DELETE_SELF
                | libc::IN_MOVED_FROM
                | libc::IN_MOVED_TO
                | libc::IN_MOVE_SELF) as u32
            != 0;
        self.push(Event {
            path: full.clone(),
            rename,
        });
        // What was created before the watch existed raised no event of its own.
        if fresh {
            self.report_existing(&full);
        }
    }

    pub fn wait(&mut self, closed: &AtomicBool) -> Res<Vec<Event>> {
        loop {
            if closed.load(Ordering::Relaxed) {
                return Err(Fail::status(STATUS_CLOSED));
            }
            self.drain();
            if let Some(f) = self.terminal.take() {
                return Err(f);
            }
            if let Some(e) = self.queue.pop_front() {
                return Ok(alloc::vec![e]);
            }
            poll_cancel();
            wait_events(self.fd);
        }
    }
}

#[cfg(target_os = "linux")]
impl Drop for Native {
    fn drop(&mut self) {
        // SAFETY: the descriptor is ours.
        unsafe { libc::close(self.fd) };
    }
}

#[cfg(target_os = "macos")]
#[path = "watch/macos.rs"]
mod native_host;
#[cfg(windows)]
#[path = "watch/windows.rs"]
mod native_host;
#[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
mod native_host {
    use super::*;

    pub struct Native;

    impl Native {
        pub fn new(_: &[u8], _: bool, _: i64, _: i64, _: &[u8]) -> Res<Native> {
            Err(Fail::status(STATUS_UNSUPPORTED))
        }

        pub fn wait(&mut self, _: &AtomicBool) -> Res<Vec<Event>> {
            Err(Fail::status(STATUS_UNSUPPORTED))
        }
    }
}
#[cfg(not(target_os = "linux"))]
pub use native_host::Native;

enum Kind {
    Poll(Poll),
    Native(Native),
}

ms_rt::ffi::abi_handle!(Watcher);

/// A `FileWatcher`.
pub struct Watcher {
    kind: Kind,
    closed: AtomicBool,
}

impl Watcher {
    pub fn poll(p: Poll) -> Watcher {
        Watcher {
            kind: Kind::Poll(p),
            closed: AtomicBool::new(false),
        }
    }

    pub fn native(n: Native) -> Watcher {
        Watcher {
            kind: Kind::Native(n),
            closed: AtomicBool::new(false),
        }
    }

    /// Waits for activity; `Closed` after `close`.
    pub fn wait(&mut self) -> Res<Vec<Event>> {
        if self.closed.load(Ordering::Relaxed) {
            return Err(Fail::status(STATUS_CLOSED));
        }
        match &mut self.kind {
            Kind::Poll(p) => p.next(&self.closed),
            Kind::Native(n) => n.wait(&self.closed),
        }
    }

    pub fn close(&mut self) {
        self.closed.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ops;
    use alloc::string::String;

    fn names(v: Vec<Event>) -> Vec<(String, bool)> {
        v.into_iter()
            .map(|e| (String::from_utf8(e.path).unwrap(), e.rename))
            .collect()
    }

    #[test]
    fn polling_reports_differences() {
        let root = ops::temporary_directory(b"msfs-poll-").unwrap();
        ops::write_file(&path::join(&root, b"a"), b"1", false).unwrap();
        assert!(Poll::new(&root, true, 0, 10).is_err());
        let mut w = Watcher::poll(Poll::new(&root, true, 10_000_000, 100).unwrap());
        ops::write_file(&path::join(&root, b"b"), b"2", false).unwrap();
        // The directory's own change is reported with the new entry, sorted by path.
        let got = names(w.wait().unwrap());
        let last = got.last().unwrap();
        assert!((last.0.ends_with("/b") || last.0.ends_with("\\b")) && last.1);
        // NTFS updates a directory's timestamp lazily, so only elsewhere is the change visible.
        if !cfg!(windows) {
            assert_eq!(got.len(), 2);
            assert!(!got[0].1);
        }
        ops::remove(&path::join(&root, b"a"), false).unwrap();
        let got = names(w.wait().unwrap());
        assert!(
            got.iter()
                .any(|(p, r)| (p.ends_with("/a") || p.ends_with("\\a")) && *r)
        );
        w.close();
        assert_eq!(w.wait().err().map(|f| f.status), Some(STATUS_CLOSED));
        let limited = Poll::new(&root, true, 10_000_000, 1);
        assert_eq!(limited.err().map(|f| f.status), Some(STATUS_LIMIT_EXCEEDED));
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn native_reports_events_and_new_directories() {
        let root = ops::temporary_directory(b"msfs-native-").unwrap();
        assert!(Native::new(&root, true, 10, 10, b"bogus").is_err());
        ops::write_file(&path::join(&root, b"a"), b"x", false).unwrap();
        // The root and one file are two paths.
        let limited = Native::new(&root, true, 1, 10, b"error");
        assert_eq!(limited.err().map(|f| f.status), Some(STATUS_LIMIT_EXCEEDED));
        drop(Native::new(&root, true, 2, 10, b"error").unwrap());
        let mut w = Watcher::native(Native::new(&root, true, 100, 100, b"error").unwrap());
        ops::create_directory(&path::join(&root, b"d"), false).unwrap();
        let got = names(w.wait().unwrap());
        assert!(
            got.iter()
                .any(|(p, r)| (p.ends_with("/d") || p.ends_with("\\d")) && *r)
        );
        ops::write_file(&path::join(&root, b"d/f"), b"x", false).unwrap();
        let mut seen = Vec::new();
        while seen
            .iter()
            .all(|(p, _): &(String, bool)| !p.ends_with("/d/f") && !p.ends_with("\\d\\f"))
        {
            seen.extend(names(w.wait().unwrap()));
        }
        w.close();
        ops::remove(&root, true).unwrap();
    }
}
