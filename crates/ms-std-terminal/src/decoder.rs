//! Terminal input bytes to events: text runs, control and named keys, and `Ctrl`/`Alt`/`Shift`
//! modifiers from CSI sequences. Bytes of an incomplete UTF-8 scalar or escape sequence stay
//! pending across `feed` calls; `flush` resolves a lone escape into the Escape key.

use alloc::vec::Vec;

/// One decoded input event; for a key, `name` is the key name.
#[derive(Debug, PartialEq, Eq)]
pub enum Event {
    Text(Vec<u8>),
    Key {
        name: Vec<u8>,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },
    Resize {
        columns: i64,
        rows: i64,
    },
}

impl Event {
    fn key(name: &str) -> Event {
        Event::Key {
            name: name.as_bytes().to_vec(),
            ctrl: false,
            alt: false,
            shift: false,
        }
    }
}

#[derive(Default)]
pub struct Decoder {
    pending: Vec<u8>,
}

/// What the start of a byte run holds.
enum Rune {
    /// A scalar value and the bytes it took (invalid input is U+FFFD over one byte).
    Char(char, usize),
    /// A valid prefix of a longer scalar.
    Incomplete,
}

fn rune(buf: &[u8]) -> Rune {
    let need = match buf[0] {
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        0x00..=0x7f => 1,
        _ => return Rune::Char('\u{fffd}', 1),
    };
    match core::str::from_utf8(&buf[..need.min(buf.len())]) {
        Ok(s) => {
            let c = s.chars().next().unwrap_or('\u{fffd}');
            Rune::Char(c, c.len_utf8())
        }
        Err(e) if e.error_len().is_none() && buf.len() < need => Rune::Incomplete,
        Err(_) => Rune::Char('\u{fffd}', 1),
    }
}

fn push_char(out: &mut Vec<u8>, c: char) {
    let mut buf = [0u8; 4];
    out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
}

fn control(b: u8) -> Event {
    match b {
        b'\r' | b'\n' => Event::key("enter"),
        b'\t' => Event::key("tab"),
        0x7f | 0x08 => Event::key("backspace"),
        0 => Event::Key {
            name: b"space".to_vec(),
            ctrl: true,
            alt: false,
            shift: false,
        },
        _ => {
            let letter = if b <= 0x1a { b'a' + b - 1 } else { b'@' + b };
            Event::Key {
                name: [letter].to_vec(),
                ctrl: true,
                alt: false,
                shift: false,
            }
        }
    }
}

/// The outcome of decoding the escape sequence at the start of a buffer.
enum Escape {
    Incomplete,
    Decoded(Event, usize),
    /// An unrecognized sequence, dropped over this many bytes.
    Dropped(usize),
}

fn tilde_key(n: i64) -> Option<&'static str> {
    Some(match n {
        1 | 7 => "home",
        2 => "insert",
        3 => "delete",
        4 | 8 => "end",
        5 => "page_up",
        6 => "page_down",
        11 => "f1",
        12 => "f2",
        13 => "f3",
        14 => "f4",
        15 => "f5",
        17 => "f6",
        18 => "f7",
        19 => "f8",
        20 => "f9",
        21 => "f10",
        23 => "f11",
        24 => "f12",
        _ => return None,
    })
}

fn letter_key(c: u8) -> Option<&'static str> {
    Some(match c {
        b'A' => "up",
        b'B' => "down",
        b'C' => "right",
        b'D' => "left",
        b'H' => "home",
        b'F' => "end",
        b'P' => "f1",
        b'Q' => "f2",
        b'R' => "f3",
        b'S' => "f4",
        _ => return None,
    })
}

/// The integer a parameter spells, or 0 (`strconv.Atoi` failures count as 0).
fn number(part: &[u8]) -> i64 {
    let (sign, digits) = match part.split_first() {
        Some((b'-', rest)) => (-1, rest),
        Some((b'+', rest)) => (1, rest),
        _ => (1, part),
    };
    if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
        return 0;
    }
    let n = digits.iter().fold(0i64, |n, &d| {
        n.saturating_mul(10).saturating_add(i64::from(d - b'0'))
    });
    sign * n
}

fn csi(params: &[u8], final_byte: u8) -> Option<Event> {
    let numbers: Vec<i64> = params.split(|&b| b == b';').map(number).collect();
    let mut event = match final_byte {
        b'Z' => {
            return Some(Event::Key {
                name: b"tab".to_vec(),
                ctrl: false,
                alt: false,
                shift: true,
            });
        }
        b'~' => Event::key(tilde_key(numbers[0])?),
        c => Event::key(letter_key(c)?),
    };
    if let (
        Some(&m),
        Event::Key {
            ctrl, alt, shift, ..
        },
    ) = (numbers.get(1), &mut event)
        && m > 1
    {
        let bits = m - 1;
        (*shift, *alt, *ctrl) = (bits & 1 != 0, bits & 2 != 0, bits & 4 != 0);
    }
    Some(event)
}

/// Decodes the sequence at the start of `buf`, which begins with ESC.
fn escape(buf: &[u8]) -> Escape {
    if buf.len() == 1 {
        return Escape::Incomplete;
    }
    match buf[1] {
        b'[' => {
            for (i, &c) in buf.iter().enumerate().skip(2) {
                if (0x40..=0x7e).contains(&c) {
                    return match csi(&buf[2..i], c) {
                        Some(event) => Escape::Decoded(event, i + 1),
                        None => Escape::Dropped(i + 1),
                    };
                }
                if !(0x20..=0x3f).contains(&c) {
                    return Escape::Dropped(i);
                }
            }
            Escape::Incomplete
        }
        b'O' => {
            let Some(&c) = buf.get(2) else {
                return Escape::Incomplete;
            };
            match letter_key(c) {
                Some(name) => Escape::Decoded(Event::key(name), 3),
                None => Escape::Dropped(3),
            }
        }
        0x1b => Escape::Decoded(Event::key("escape"), 1),
        _ => {
            // Escape followed by a key is that key with Alt held.
            let (c, n) = match rune(&buf[1..]) {
                Rune::Incomplete => return Escape::Incomplete,
                Rune::Char(c, n) => (c, n),
            };
            let mut event = match c {
                '\0'..='\u{1f}' | '\u{7f}' => control(c as u8),
                ' ' => Event::key("space"),
                _ => {
                    let mut name = Vec::new();
                    push_char(&mut name, c);
                    Event::Key {
                        name,
                        ctrl: false,
                        alt: false,
                        shift: false,
                    }
                }
            };
            if let Event::Key { alt, .. } = &mut event {
                *alt = true;
            }
            Escape::Decoded(event, 1 + n)
        }
    }
}

impl Decoder {
    pub fn pending(&self) -> bool {
        !self.pending.is_empty()
    }

    /// Treats pending input as final: a lone escape is the Escape key and any other incomplete
    /// escape sequence is dropped. A partial UTF-8 scalar is kept: a terminal never ends one
    /// early, so its remaining bytes can still arrive on a slow link.
    pub fn flush(&mut self) -> Vec<Event> {
        if self.pending.first() != Some(&0x1b) {
            return Vec::new();
        }
        let lone = self.pending == [0x1b];
        self.pending.clear();
        if lone {
            alloc::vec![Event::key("escape")]
        } else {
            Vec::new()
        }
    }

    /// Decodes `data`. Invalid UTF-8 becomes U+FFFD; unrecognized escape sequences are dropped
    /// whole so they never leak as text.
    pub fn feed(&mut self, data: &[u8]) -> Vec<Event> {
        let mut input = core::mem::take(&mut self.pending);
        input.extend_from_slice(data);
        let mut buf = input.as_slice();
        let mut out = Vec::new();
        let mut text = Vec::new();
        fn flush_text(out: &mut Vec<Event>, text: &mut Vec<u8>) {
            if !text.is_empty() {
                out.push(Event::Text(core::mem::take(text)));
            }
        }
        while let Some(&b) = buf.first() {
            if b == 0x1b {
                flush_text(&mut out, &mut text);
                match escape(buf) {
                    Escape::Incomplete => {
                        self.pending = buf.to_vec();
                        return out;
                    }
                    Escape::Decoded(event, n) => {
                        out.push(event);
                        buf = &buf[n..];
                    }
                    Escape::Dropped(n) => buf = &buf[n..],
                }
            } else if b < 0x20 || b == 0x7f {
                flush_text(&mut out, &mut text);
                out.push(control(b));
                buf = &buf[1..];
            } else {
                match rune(buf) {
                    Rune::Incomplete => {
                        flush_text(&mut out, &mut text);
                        self.pending = buf.to_vec();
                        return out;
                    }
                    Rune::Char(c, n) => {
                        push_char(&mut text, c);
                        buf = &buf[n..];
                    }
                }
            }
        }
        flush_text(&mut out, &mut text);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn key(name: &str, ctrl: bool, alt: bool, shift: bool) -> Event {
        Event::Key {
            name: name.as_bytes().to_vec(),
            ctrl,
            alt,
            shift,
        }
    }

    fn text(s: &str) -> Event {
        Event::Text(s.as_bytes().to_vec())
    }

    #[test]
    fn text_and_controls() {
        let mut d = Decoder::default();
        assert_eq!(
            d.feed(b"ab\r\x03\x7f\0"),
            vec![
                text("ab"),
                key("enter", false, false, false),
                key("c", true, false, false),
                key("backspace", false, false, false),
                key("space", true, false, false),
            ]
        );
    }

    #[test]
    fn utf8_split_across_reads() {
        let mut d = Decoder::default();
        assert_eq!(d.feed(&"é".as_bytes()[..1]), vec![]);
        assert!(d.pending());
        assert_eq!(d.feed(&"é".as_bytes()[1..]), vec![text("é")]);
        assert_eq!(d.feed(&[0xff, b'x']), vec![text("\u{fffd}x")]);
    }

    #[test]
    fn flush_keeps_a_partial_scalar() {
        let mut d = Decoder::default();
        assert_eq!(d.feed(&"€".as_bytes()[..2]), vec![]);
        assert_eq!(d.flush(), vec![]);
        assert!(d.pending());
        assert_eq!(d.feed(&"€".as_bytes()[2..]), vec![text("€")]);
        assert_eq!(d.feed(b"\x1b"), vec![]);
        assert_eq!(d.flush(), vec![key("escape", false, false, false)]);
        assert!(!d.pending());
    }

    #[test]
    fn named_and_modified_keys() {
        let mut d = Decoder::default();
        assert_eq!(
            d.feed(b"\x1b[A\x1bOP\x1b[3~\x1b[1;5C\x1b[Z\x1b[24~"),
            vec![
                key("up", false, false, false),
                key("f1", false, false, false),
                key("delete", false, false, false),
                key("right", true, false, false),
                key("tab", false, false, true),
                key("f12", false, false, false),
            ]
        );
        assert_eq!(
            d.feed(b"\x1bx\x1b "),
            vec![
                key("x", false, true, false),
                key("space", false, true, false),
            ]
        );
    }

    #[test]
    fn escape_waits_for_a_flush_and_unknown_sequences_are_dropped() {
        let mut d = Decoder::default();
        assert_eq!(d.feed(b"\x1b"), vec![]);
        assert!(d.pending());
        assert_eq!(d.flush(), vec![key("escape", false, false, false)]);
        assert!(!d.pending());
        assert_eq!(d.feed(b"\x1b[9999~a"), vec![text("a")]);
        assert_eq!(d.feed(b"\x1b[1;"), vec![]);
        assert_eq!(d.flush(), vec![]);
    }
}
