#![cfg(unix)]
// The pseudo-terminal is driven through libc.
#![allow(unsafe_code)]
//! `RawTerminal` end to end: a built program runs on a pseudo-terminal that the test types into.

use std::fs::File;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const PROGRAM: &str = r#"from "@std/io.ms" import terminal, TerminalEvent, EraseRegion
from "@std/io.ms" import stdout
from "@std/time.ms" import duration

def describe(e: TerminalEvent) -> String:
    match e:
        case Text(t): return "text:" + t
        case Key(n, c, a, s): return "key:" + n + f" ctrl={c} alt={a} shift={s}"
        case Resize(c, r): return f"resize:{c}x{r}"

export def main() -> Int:
    let raw = terminal().raw_mode(alternate_screen: False)
    if let t = raw:
        with t as term:
            term.move_cursor(1, 2)
            term.show_cursor(False)
            term.erase(EraseRegion.LineEnd)
            if let size = term.size():
                stdout().write(f"size {size.columns}x{size.rows}\r\n")
            var done = False
            while not done:
                let next = term.next_event(duration(5000000000))
                if let maybe = next:
                    if let e = maybe:
                        stdout().write(describe(e.clone()) + "\r\n")
                        done = describe(e) == "text:q"
                    else:
                        stdout().write("timeout\r\n")
                        done = True
                else:
                    stdout().write("error\r\n")
                    done = True
        return 0
    stdout().write("no raw mode\n")
    return 1
"#;

fn winsize(rows: u16, columns: u16) -> libc::winsize {
    libc::winsize {
        ws_row: rows,
        ws_col: columns,
        ws_xpixel: 0,
        ws_ypixel: 0,
    }
}

/// Reads from the pseudo-terminal until `needle` shows up in the accumulated output.
fn wait_for(master: &File, log: &mut String, needle: &str) {
    let deadline = Instant::now() + Duration::from_secs(20);
    while !log.contains(needle) {
        assert!(Instant::now() < deadline, "no {needle:?} in {log:?}");
        let mut p = libc::pollfd {
            fd: master.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one valid pollfd.
        if unsafe { libc::poll(&mut p, 1, 100) } <= 0 {
            continue;
        }
        let mut buf = [0u8; 1024];
        // SAFETY: `buf` is writable for its length.
        let n = unsafe { libc::read(master.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
        if n <= 0 {
            break;
        }
        log.push_str(&String::from_utf8_lossy(&buf[..n as usize]));
    }
    assert!(log.contains(needle), "no {needle:?} in {log:?}");
}

fn type_bytes(master: &File, bytes: &[u8]) {
    // SAFETY: `bytes` is readable for its length.
    let n = unsafe { libc::write(master.as_raw_fd(), bytes.as_ptr().cast(), bytes.len()) };
    assert_eq!(n as usize, bytes.len());
}

#[test]
fn raw_terminal_reads_keys_resizes_and_restores_the_terminal() {
    let dir = std::env::temp_dir().join(format!("ms-terminal-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(&source, PROGRAM).unwrap();
    let program = dir.join("program");
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("build")
        .arg(&source)
        .arg("-o")
        .arg(&program)
        .output()
        .unwrap();
    assert!(built.status.success(), "{built:?}");

    // SAFETY: plain system calls; every descriptor is owned by a `File` or `OwnedFd` below.
    let (master, slave) = unsafe {
        let m = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY);
        assert!(m >= 0);
        assert_eq!(libc::grantpt(m), 0);
        assert_eq!(libc::unlockpt(m), 0);
        // `ptsname_r` is missing on macOS; the test thread is the only caller here.
        let name = libc::ptsname(m);
        assert!(!name.is_null());
        let s = libc::open(name, libc::O_RDWR | libc::O_NOCTTY);
        assert!(s >= 0);
        assert_eq!(libc::ioctl(m, libc::TIOCSWINSZ, &winsize(24, 80)), 0);
        (File::from_raw_fd(m), OwnedFd::from_raw_fd(s))
    };
    let canonical = |fd: i32| {
        // SAFETY: `termios` is plain data that `tcgetattr` fills.
        let mut t: libc::termios = unsafe { std::mem::zeroed() };
        // SAFETY: `t` is writable.
        assert_eq!(unsafe { libc::tcgetattr(fd, &mut t) }, 0);
        t.c_lflag & libc::ICANON != 0
    };
    assert!(canonical(slave.as_raw_fd()));
    let mut child = Command::new(&program)
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap()))
        .spawn()
        .unwrap();

    let mut log = String::new();
    wait_for(&master, &mut log, "size 80x24");
    assert!(!canonical(slave.as_raw_fd()), "raw mode is on");
    for (keys, expected) in [
        (&b"ab"[..], "text:ab"),
        (b"\x1b[A", "key:up ctrl=false alt=false shift=false"),
        (b"\x03", "key:c ctrl=true alt=false shift=false"),
        (b"\x1b", "key:escape ctrl=false alt=false shift=false"),
        (b"\x1b[1;5C", "key:right ctrl=true alt=false shift=false"),
    ] {
        type_bytes(&master, keys);
        wait_for(&master, &mut log, expected);
    }
    // SAFETY: `winsize` is readable.
    let rc = unsafe { libc::ioctl(master.as_raw_fd(), libc::TIOCSWINSZ, &winsize(30, 100)) };
    assert_eq!(rc, 0);
    wait_for(&master, &mut log, "resize:100x30");
    type_bytes(&master, b"q");
    wait_for(&master, &mut log, "text:q");
    // The `with` scope shows the cursor again and the terminal settings come back.
    wait_for(&master, &mut log, "\x1b[?25h");
    assert!(child.wait().unwrap().success());
    assert!(canonical(slave.as_raw_fd()), "settings restored");
    assert!(log.starts_with("\x1b[2;3H\x1b[?25l\x1b[K"), "{log:?}");
    let _ = std::fs::remove_dir_all(&dir);
}
