//! Raw terminal tests over a pseudo-terminal: the program side is the slave, the "user" types
//! into the master.
extern crate std;

use super::*;
use ms_rt as _; // links the msrt_* runtime symbols
use ms_rt_abi::STATUS_OK;
use rustix::event::{PollFd, PollFlags, poll};
use rustix::fd::{AsFd, BorrowedFd, OwnedFd};
use rustix::fs::{Mode, OFlags};
use rustix::io::{read, write};
use rustix::pty::{OpenptFlags, grantpt, openpt, ptsname, unlockpt};
use rustix::termios::tcgetattr;
use rustix::termios::{LocalModes, Winsize, tcsetwinsize};
use rustix::time::Timespec;
use std::boxed::Box;
use std::sync::Mutex;
use std::vec::Vec;

/// The status a command ended with.
fn readable_now(fd: BorrowedFd<'_>) -> bool {
    let mut fds = [PollFd::new(&fd, PollFlags::IN)];
    let zero = Timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    poll(&mut fds, Some(&zero)).is_ok_and(|n| n > 0)
}

/// The status a command ended with.
fn code(r: Result<(), Failure>) -> u8 {
    r.err().map_or(STATUS_OK, |f| f.status)
}

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

fn attach(pty: &Pty) -> Result<Raw, Failure> {
    let (input, output) = (pty.fd(), pty.fd());
    Raw::attach(|| Term::open(input, output))
}

fn read_text(raw: &Raw, timeout_ms: i64) -> (u8, String) {
    let mut text = String::new();
    let status = raw.read(timeout_ms < 50, &mut text);
    (status, text)
}

#[test]
fn raw_mode_reads_text_and_restores_settings() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let before = pty.local_modes();
    assert!(before.contains(LocalModes::ICANON));
    let raw = attach(&pty).expect("raw terminal");
    assert!(
        !pty.local_modes()
            .intersects(LocalModes::ICANON | LocalModes::ECHO | LocalModes::ISIG)
    );
    pty.type_text("h\u{e9}\x1b[A".as_bytes());
    assert_eq!(read_text(&raw, 500), (STATUS_OK, "h\u{e9}\x1b[A".into()));
    assert_eq!(read_text(&raw, 0).0, STATUS_NONE);
    raw.set_restore(b"bye");
    raw.close();
    raw.close();
    // macOS raises PENDIN while it retypes input queued across a mode change.
    let settled = |m: LocalModes| m.difference(LocalModes::PENDIN);
    assert_eq!(settled(pty.local_modes()), settled(before));
    assert_eq!(pty.output(), b"bye".to_vec());
    assert_eq!(read_text(&raw, 10).0, STATUS_CLOSED);
    assert_eq!(raw.size(), Err(STATUS_CLOSED));
    assert_eq!(code(raw.command(b"x")), STATUS_CLOSED);
}

#[test]
fn a_scalar_split_across_reads_arrives_whole_and_bad_bytes_are_replaced() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let raw = attach(&pty).expect("raw terminal");
    pty.type_text(&[0xe2, 0x82]);
    assert_eq!(read_text(&raw, 50).0, STATUS_NONE);
    pty.type_text(&[0xac, 0xff, b'a']);
    assert_eq!(
        read_text(&raw, 500),
        (STATUS_OK, "\u{20ac}\u{fffd}a".into())
    );
}

#[test]
fn commands_write_text_and_the_registered_restore_text_runs_on_drop() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let raw = attach(&pty).expect("raw terminal");
    assert_eq!(code(raw.command(b"\x1b[3;10H")), STATUS_OK);
    assert_eq!(raw.size(), Ok((80, 24)));
    raw.set_restore(b"\x1b[?25h");
    assert_eq!(pty.output(), b"\x1b[3;10H".to_vec());
    drop(raw);
    assert_eq!(pty.output(), b"\x1b[?25h".to_vec());
}

#[test]
fn one_raw_terminal_at_a_time_and_a_resized_window_reports_its_size() {
    let _turn = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let pty = Pty::new();
    let raw = attach(&pty).expect("raw terminal");
    assert_eq!(
        attach(&pty).err().map(|f| f.status),
        Some(ms_rt_abi::STATUS_BUSY)
    );
    tcsetwinsize(&pty.master, window(30, 100)).expect("set size");
    assert_eq!(raw.size(), Ok((100, 30)));
    drop(raw);
    drop(attach(&pty).expect("reopened"));
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
        Raw::attach(|| Term::open(read_end.as_fd(), write_end.as_fd()))
            .err()
            .map(|f| f.status),
        Some(STATUS_NOT_TERMINAL)
    );
}
