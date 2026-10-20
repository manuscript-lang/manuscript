//! Raw terminal tests over a pseudo-terminal: the program side is the slave, the "user" types
//! into the master.
extern crate std;

use super::*;
use ms_rt as _; // links the msrt_* runtime symbols
use rustix::fd::{AsFd, OwnedFd};
use rustix::fs::{Mode, OFlags};
use rustix::pty::{OpenptFlags, grantpt, openpt, ptsname, unlockpt};
use rustix::termios::{LocalModes, Winsize, tcsetwinsize};
use std::boxed::Box;
use std::sync::Mutex;
use std::vec::Vec;

/// One raw terminal may be open at a time, so the tests take turns.
static TURN: Mutex<()> = Mutex::new(());

struct Pty {
    master: OwnedFd,
    /// Leaked so the raw terminal can borrow it for `'static`; tests are short-lived.
    slave: &'static OwnedFd,
}

impl Pty {
    fn new() -> Pty {
        let master = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY).expect("openpt");
        grantpt(&master).expect("grantpt");
        unlockpt(&master).expect("unlockpt");
        let name = ptsname(&master, Vec::new()).expect("ptsname");
        let slave = rustix::fs::open(
            name.as_c_str(),
            OFlags::RDWR | OFlags::NOCTTY,
            Mode::empty(),
        )
        .expect("open slave");
        tcsetwinsize(&master, window(24, 80)).expect("set size");
        Pty {
            master,
            slave: Box::leak(Box::new(slave)),
        }
    }

    fn fd(&self) -> BorrowedFd<'static> {
        self.slave.as_fd()
    }

    fn type_text(&self, bytes: &[u8]) {
        assert_eq!(write(&self.master, bytes), Ok(bytes.len()));
    }

    /// Everything the program has written so far.
    fn output(&self) -> Vec<u8> {
        let mut out = Vec::new();
        let mut buf = [0u8; 256];
        while readable_now(self.master.as_fd()) {
            match read(&self.master, &mut buf[..]) {
                Ok(n) if n > 0 => out.extend_from_slice(&buf[..n]),
                _ => break,
            }
        }
        out
    }

    fn local_modes(&self) -> LocalModes {
        tcgetattr(self.slave).expect("tcgetattr").local_modes
    }
}

fn window(rows: u16, columns: u16) -> Winsize {
    Winsize {
        ws_row: rows,
        ws_col: columns,
        ws_xpixel: 0,
        ws_ypixel: 0,
    }
}

fn open(pty: &Pty, alternate: bool) -> *mut ms_std_rt::Handle<Raw> {
    Raw::open(pty.fd(), pty.fd(), alternate).expect("raw terminal")
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
    let before = pty.local_modes();
    assert!(before.contains(LocalModes::ICANON));
    let h = open(&pty, false);
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    assert!(
        !pty.local_modes()
            .intersects(LocalModes::ICANON | LocalModes::ECHO | LocalModes::ISIG)
    );
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
    assert_eq!(pty.local_modes(), before);
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
        Raw::open(pty.fd(), pty.fd(), false).err(),
        Some(ms_rt_abi::STATUS_BUSY)
    );
    // SAFETY: `h` is live until released below.
    let raw = unsafe { &(*h).value };
    tcsetwinsize(&pty.master, window(30, 100)).expect("set size");
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
    let (read_end, write_end) = rustix::pipe::pipe().expect("pipe");
    let (read_end, write_end): (&'static OwnedFd, &'static OwnedFd) = (
        Box::leak(Box::new(read_end)),
        Box::leak(Box::new(write_end)),
    );
    assert_eq!(
        Raw::open(read_end.as_fd(), write_end.as_fd(), false).err(),
        Some(STATUS_NOT_TERMINAL)
    );
}
