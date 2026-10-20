//! Raw terminal tests over a pseudo-terminal: the program side is the slave, the "user" types
//! into the master.
extern crate std;

use super::*;
use ms_rt as _; // links the msrt_* runtime symbols
use std::sync::Mutex;

/// One raw terminal may be open at a time, so the tests take turns.
static TURN: Mutex<()> = Mutex::new(());

struct Pty {
    master: i32,
    slave: i32,
}

impl Pty {
    fn new() -> Pty {
        // SAFETY: plain system calls on descriptors owned here.
        unsafe {
            let master = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY);
            assert!(master >= 0);
            assert_eq!(libc::grantpt(master), 0);
            assert_eq!(libc::unlockpt(master), 0);
            let mut name = [0 as libc::c_char; 128];
            assert_eq!(libc::ptsname_r(master, name.as_mut_ptr(), name.len()), 0);
            let slave = libc::open(name.as_ptr(), libc::O_RDWR | libc::O_NOCTTY);
            assert!(slave >= 0);
            let size = libc::winsize {
                ws_row: 24,
                ws_col: 80,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            assert_eq!(libc::ioctl(master, libc::TIOCSWINSZ, &size), 0);
            Pty { master, slave }
        }
    }

    fn type_text(&self, bytes: &[u8]) {
        // SAFETY: `bytes` is readable for its length.
        let n = unsafe { libc::write(self.master, bytes.as_ptr().cast(), bytes.len()) };
        assert_eq!(n as usize, bytes.len());
    }

    /// Everything the program has written so far.
    fn output(&self) -> std::vec::Vec<u8> {
        let mut out = std::vec::Vec::new();
        let mut buf = [0u8; 256];
        while readable_now(self.master) {
            // SAFETY: `buf` is writable for its length.
            let n = unsafe { libc::read(self.master, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                break;
            }
            out.extend_from_slice(&buf[..n as usize]);
        }
        out
    }

    fn lflag(&self) -> libc::tcflag_t {
        // SAFETY: `termios` is plain data that `tcgetattr` fills.
        let mut t: libc::termios = unsafe { core::mem::zeroed() };
        // SAFETY: `t` is writable.
        assert_eq!(unsafe { libc::tcgetattr(self.slave, &mut t) }, 0);
        t.c_lflag
    }
}

impl Drop for Pty {
    fn drop(&mut self) {
        // SAFETY: both descriptors are open and owned here.
        unsafe {
            libc::close(self.slave);
            libc::close(self.master);
        }
    }
}

fn open(pty: &Pty, alternate: bool) -> *mut ms_std_rt::Handle<Raw> {
    Raw::open(pty.slave, pty.slave, alternate).expect("raw terminal")
}

fn next(raw: &Raw, timeout_ms: Option<i64>) -> (u8, Option<Event>) {
    let mut current = None;
    let status = raw.next_event(timeout_ms.map(|ms| ms * NS_PER_MS), &mut current);
    (status, current)
}

fn release(h: *mut ms_std_rt::Handle<Raw>) {
    // SAFETY: `h` came from `Raw::open` and is released once.
    unsafe { core::ptr::drop_in_place(&mut (*h).value) };
}

fn key(name: &str) -> Event {
    Event::Key {
        name: name.as_bytes().to_vec(),
        ctrl: false,
        alt: false,
        shift: false,
    }
}

#[test]
fn raw_mode_decodes_input_and_restores_settings() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let before = pty.lflag();
    assert_ne!(before & libc::ICANON, 0);
    let h = open(&pty, false);
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    assert_eq!(pty.lflag() & (libc::ICANON | libc::ECHO | libc::ISIG), 0);
    pty.type_text(b"hi\x1b[A");
    assert_eq!(
        next(raw, Some(500)),
        (STATUS_OK, Some(Event::Text(b"hi".to_vec())))
    );
    assert_eq!(next(raw, Some(500)), (STATUS_OK, Some(key("up"))));
    assert_eq!(next(raw, Some(0)).0, STATUS_NONE);
    assert_eq!(next(raw, Some(20)).0, STATUS_NONE);
    raw.close();
    raw.close();
    assert_eq!(pty.lflag(), before);
    assert_eq!(next(raw, None).0, STATUS_CLOSED);
    assert_eq!(raw.size(), Err(STATUS_CLOSED));
    assert_eq!(raw.move_cursor(0, 0), STATUS_CLOSED);
    release(h);
}

#[test]
fn a_lone_escape_becomes_the_escape_key() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let h = open(&pty, false);
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    pty.type_text(b"\x1b");
    assert_eq!(next(raw, Some(1000)), (STATUS_OK, Some(key("escape"))));
    release(h);
}

#[test]
fn cursor_and_screen_commands_write_escape_sequences() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let h = open(&pty, true);
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    assert_eq!(raw.move_cursor(2, 9), STATUS_OK);
    assert_eq!(raw.move_cursor(-1, 0), STATUS_INVALID_INPUT);
    assert_eq!(raw.move_cursor(0, 70_000), STATUS_INVALID_INPUT);
    assert_eq!(raw.show_cursor(false), STATUS_OK);
    for region in 0..4 {
        assert_eq!(raw.erase(region), STATUS_OK);
    }
    assert_eq!(raw.size(), Ok((80, 24)));
    assert_eq!(
        pty.output(),
        b"\x1b[?1049h\x1b[3;10H\x1b[?25l\x1b[2J\x1b[2K\x1b[K\x1b[1K".to_vec()
    );
    // Dropping the last reference restores the terminal like `close`.
    release(h);
    assert_eq!(pty.output(), b"\x1b[?25h\x1b[?1049l".to_vec());
}

#[test]
fn one_raw_terminal_at_a_time_and_resize_events() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let h = open(&pty, false);
    assert_eq!(
        Raw::open(pty.slave, pty.slave, false).err(),
        Some(ms_rt_abi::STATUS_BUSY)
    );
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    let size = libc::winsize {
        ws_row: 30,
        ws_col: 100,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    // SAFETY: `size` is readable.
    let rc = unsafe { libc::ioctl(pty.master, libc::TIOCSWINSZ, &size) };
    assert_eq!(rc, 0);
    let resize = Event::Resize {
        columns: 100,
        rows: 30,
    };
    assert_eq!(next(raw, Some(1000)), (STATUS_OK, Some(resize)));
    release(h);
    release(open(&pty, false));
}

#[test]
fn redirected_streams_are_not_terminals() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    assert_eq!(Raw::open(-1, -1, false).err(), Some(STATUS_NOT_TERMINAL));
}
