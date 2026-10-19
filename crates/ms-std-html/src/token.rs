//! The HTML5 tokenizer, ported from `golang.org/x/net/html/token.go` over an in-memory input.
use crate::atoms::ATOMS;
use crate::escape::unescape;
use alloc::string::String;
use alloc::vec::Vec;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TokenType {
    Error,
    Text,
    StartTag,
    EndTag,
    SelfClosingTag,
    Comment,
    Doctype,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Attribute {
    pub namespace: String,
    pub key: String,
    pub val: String,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub ty: TokenType,
    /// The tag name when it is a known atom, otherwise empty (Go's zero `DataAtom`).
    pub atom: String,
    pub data: String,
    pub attr: Vec<Attribute>,
}

/// The atom for `name` (a lower-case tag name), or empty when `name` is not a known atom.
pub fn atom_of(name: &str) -> String {
    if ATOMS
        .binary_search_by(|a| a.as_bytes().cmp(name.as_bytes()))
        .is_ok()
    {
        String::from(name)
    } else {
        String::new()
    }
}

#[derive(Clone, Copy, Default)]
struct Span {
    start: usize,
    end: usize,
}

pub struct Tokenizer {
    buf: Vec<u8>,
    tt: TokenType,
    eof: bool,
    raw: Span,
    data: Span,
    pending_attr: [Span; 2],
    attr: Vec<[Span; 2]>,
    n_attr_returned: usize,
    raw_tag: &'static str,
    text_is_raw: bool,
    convert_nul: bool,
    allow_cdata: bool,
}

fn is_space(c: u8) -> bool {
    matches!(c, b' ' | b'\n' | b'\r' | b'\t' | 0x0c)
}

fn is_alpha(c: u8) -> bool {
    c.is_ascii_alphabetic()
}

/// Converts `\r` and `\r\n` to `\n`.
fn convert_newlines(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if s[i] == b'\r' {
            out.push(b'\n');
            if s.get(i + 1) == Some(&b'\n') {
                i += 1;
            }
        } else {
            out.push(s[i]);
        }
        i += 1;
    }
    out
}

fn lossy(b: Vec<u8>) -> String {
    String::from_utf8(b).unwrap_or_else(|e| String::from_utf8_lossy(e.as_bytes()).into_owned())
}

#[derive(Clone, Copy)]
enum Script {
    Data,
    LessThan,
    EndTagOpen,
    EscapeStart,
    EscapeStartDash,
    Escaped,
    EscapedDash,
    EscapedDashDash,
    EscapedLessThan,
    EscapedEndTagOpen,
    DoubleEscapeStart,
    DoubleEscaped,
    DoubleEscapedDash,
    DoubleEscapedDashDash,
    DoubleEscapedLessThan,
    DoubleEscapeEnd,
}

impl Tokenizer {
    pub fn new(input: &[u8]) -> Self {
        Self {
            buf: input.to_vec(),
            tt: TokenType::Error,
            eof: false,
            raw: Span::default(),
            data: Span::default(),
            pending_attr: [Span::default(); 2],
            attr: Vec::new(),
            n_attr_returned: 0,
            raw_tag: "",
            text_is_raw: false,
            convert_nul: false,
            allow_cdata: false,
        }
    }

    pub fn allow_cdata(&mut self, allow: bool) {
        self.allow_cdata = allow;
    }

    pub fn next_is_not_raw_text(&mut self) {
        self.raw_tag = "";
    }

    /// Whether the input is exhausted (Go's `z.err != nil`).
    fn failed(&self) -> bool {
        self.eof
    }

    fn read_byte(&mut self) -> u8 {
        if self.raw.end >= self.buf.len() {
            self.eof = true;
            return 0;
        }
        let x = self.buf[self.raw.end];
        self.raw.end += 1;
        x
    }

    fn skip_white_space(&mut self) {
        if self.eof {
            return;
        }
        loop {
            let c = self.read_byte();
            if self.eof {
                return;
            }
            if !is_space(c) {
                self.raw.end -= 1;
                return;
            }
        }
    }

    fn read_raw_or_rcdata(&mut self) {
        if self.raw_tag == "script" {
            self.read_script();
            self.text_is_raw = true;
            self.raw_tag = "";
            return;
        }
        loop {
            let c = self.read_byte();
            if self.eof {
                break;
            }
            if c != b'<' {
                continue;
            }
            let c = self.read_byte();
            if self.eof {
                break;
            }
            if c != b'/' {
                self.raw.end -= 1;
                continue;
            }
            if self.read_raw_end_tag() || self.eof {
                break;
            }
        }
        self.data.end = self.raw.end;
        self.text_is_raw = self.raw_tag != "textarea" && self.raw_tag != "title";
        self.raw_tag = "";
    }

    fn read_raw_end_tag(&mut self) -> bool {
        let tag = self.raw_tag.as_bytes();
        for &t in tag {
            let c = self.read_byte();
            if self.eof {
                return false;
            }
            if c != t && c != t - (b'a' - b'A') {
                self.raw.end -= 1;
                return false;
            }
        }
        let c = self.read_byte();
        if self.eof {
            return false;
        }
        if is_space(c) || c == b'/' || c == b'>' {
            self.raw.end -= 3 + tag.len();
            return true;
        }
        self.raw.end -= 1;
        false
    }

    fn read_script(&mut self) {
        use Script::*;
        let mut st = Data;
        loop {
            st = match st {
                Data => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    if c == b'<' { LessThan } else { Data }
                }
                LessThan => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'/' => EndTagOpen,
                        b'!' => EscapeStart,
                        _ => {
                            self.raw.end -= 1;
                            Data
                        }
                    }
                }
                EndTagOpen => {
                    if self.read_raw_end_tag() || self.eof {
                        break;
                    }
                    Data
                }
                EscapeStart => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    if c == b'-' {
                        EscapeStartDash
                    } else {
                        self.raw.end -= 1;
                        Data
                    }
                }
                EscapeStartDash => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    if c == b'-' {
                        EscapedDashDash
                    } else {
                        self.raw.end -= 1;
                        Data
                    }
                }
                Escaped => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => EscapedDash,
                        b'<' => EscapedLessThan,
                        _ => Escaped,
                    }
                }
                EscapedDash => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => EscapedDashDash,
                        b'<' => EscapedLessThan,
                        _ => Escaped,
                    }
                }
                EscapedDashDash => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => EscapedDashDash,
                        b'<' => EscapedLessThan,
                        b'>' => Data,
                        _ => Escaped,
                    }
                }
                EscapedLessThan => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    if c == b'/' {
                        EscapedEndTagOpen
                    } else if is_alpha(c) {
                        DoubleEscapeStart
                    } else {
                        self.raw.end -= 1;
                        Data
                    }
                }
                EscapedEndTagOpen => {
                    if self.read_raw_end_tag() || self.eof {
                        break;
                    }
                    Escaped
                }
                DoubleEscapeStart => {
                    self.raw.end -= 1;
                    let mut next = None;
                    for &t in b"script" {
                        let c = self.read_byte();
                        if self.eof {
                            self.data.end = self.raw.end;
                            return;
                        }
                        if c != t && c != t.to_ascii_uppercase() {
                            self.raw.end -= 1;
                            next = Some(Escaped);
                            break;
                        }
                    }
                    match next {
                        Some(n) => n,
                        None => {
                            let c = self.read_byte();
                            if self.eof {
                                break;
                            }
                            if is_space(c) || c == b'/' || c == b'>' {
                                DoubleEscaped
                            } else {
                                self.raw.end -= 1;
                                Escaped
                            }
                        }
                    }
                }
                DoubleEscaped => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => DoubleEscapedDash,
                        b'<' => DoubleEscapedLessThan,
                        _ => DoubleEscaped,
                    }
                }
                DoubleEscapedDash => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => DoubleEscapedDashDash,
                        b'<' => DoubleEscapedLessThan,
                        _ => DoubleEscaped,
                    }
                }
                DoubleEscapedDashDash => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    match c {
                        b'-' => DoubleEscapedDashDash,
                        b'<' => DoubleEscapedLessThan,
                        b'>' => Data,
                        _ => DoubleEscaped,
                    }
                }
                DoubleEscapedLessThan => {
                    let c = self.read_byte();
                    if self.eof {
                        break;
                    }
                    if c == b'/' {
                        DoubleEscapeEnd
                    } else {
                        self.raw.end -= 1;
                        DoubleEscaped
                    }
                }
                DoubleEscapeEnd => {
                    if self.read_raw_end_tag() {
                        self.raw.end += "</script>".len();
                        Escaped
                    } else if self.eof {
                        break;
                    } else {
                        DoubleEscaped
                    }
                }
            };
        }
        self.data.end = self.raw.end;
    }

    fn read_comment(&mut self) {
        self.data.start = self.raw.end;
        let mut dash_count = 0;
        let mut beginning = true;
        loop {
            let mut c = self.read_byte();
            if self.eof {
                self.data.end = self.calculate_abrupt_comment_data_end();
                break;
            }
            match c {
                b'-' => {
                    dash_count += 1;
                    continue;
                }
                b'>' => {
                    if dash_count >= 2 || beginning {
                        self.data.end = self.raw.end - 3;
                        break;
                    }
                }
                b'!' if dash_count >= 2 => {
                    c = self.read_byte();
                    if self.eof {
                        self.data.end = self.calculate_abrupt_comment_data_end();
                        break;
                    } else if c == b'>' {
                        self.data.end = self.raw.end - 4;
                        break;
                    } else if c == b'-' {
                        dash_count = 1;
                        beginning = false;
                        continue;
                    }
                }
                _ => {}
            }
            dash_count = 0;
            beginning = false;
        }
        if self.data.end < self.data.start {
            self.data.end = self.data.start;
        }
    }

    fn calculate_abrupt_comment_data_end(&self) -> usize {
        let raw = &self.buf[self.raw.start..self.raw.end];
        if raw.len() >= 4 {
            let raw = &raw[4..];
            if raw.ends_with(b"--!") {
                return self.raw.end - 3;
            } else if raw.ends_with(b"--") {
                return self.raw.end - 2;
            } else if raw.ends_with(b"-") {
                return self.raw.end - 1;
            }
        }
        self.raw.end
    }

    fn read_until_close_angle(&mut self) {
        self.data.start = self.raw.end;
        loop {
            let c = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return;
            }
            if c == b'>' {
                self.data.end = self.raw.end - 1;
                return;
            }
        }
    }

    fn read_markup_declaration(&mut self) -> TokenType {
        self.data.start = self.raw.end;
        let mut c = [0u8; 2];
        for b in &mut c {
            *b = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return TokenType::Comment;
            }
        }
        if c == *b"--" {
            self.read_comment();
            return TokenType::Comment;
        }
        self.raw.end -= 2;
        if self.read_doctype() {
            return TokenType::Doctype;
        }
        if self.allow_cdata && self.read_cdata() {
            self.convert_nul = true;
            return TokenType::Text;
        }
        self.read_until_close_angle();
        TokenType::Comment
    }

    fn read_doctype(&mut self) -> bool {
        for &s in b"DOCTYPE" {
            let c = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return false;
            }
            if c != s && c != s + (b'a' - b'A') {
                self.raw.end = self.data.start;
                return false;
            }
        }
        self.skip_white_space();
        if self.eof {
            self.data.start = self.raw.end;
            self.data.end = self.raw.end;
            return true;
        }
        self.read_until_close_angle();
        true
    }

    fn read_cdata(&mut self) -> bool {
        for &s in b"[CDATA[" {
            let c = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return false;
            }
            if c != s {
                self.raw.end = self.data.start;
                return false;
            }
        }
        self.data.start = self.raw.end;
        let mut brackets = 0;
        loop {
            let c = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return true;
            }
            match c {
                b']' => brackets += 1,
                b'>' => {
                    if brackets >= 2 {
                        self.data.end = self.raw.end - 3;
                        return true;
                    }
                    brackets = 0;
                }
                _ => brackets = 0,
            }
        }
    }

    fn start_tag_in(&self, ss: &[&str]) -> bool {
        let name = &self.buf[self.data.start..self.data.end];
        ss.iter().any(|s| name.eq_ignore_ascii_case(s.as_bytes()))
    }

    fn read_start_tag(&mut self) -> TokenType {
        self.read_tag(true);
        if self.eof {
            return TokenType::Error;
        }
        let c = self.buf[self.data.start].to_ascii_lowercase();
        let raw = match c {
            b'i' => self.start_tag_in(&["iframe"]),
            b'n' => self.start_tag_in(&["noembed", "noframes", "noscript"]),
            b'p' => self.start_tag_in(&["plaintext"]),
            b's' => self.start_tag_in(&["script", "style"]),
            b't' => self.start_tag_in(&["textarea", "title"]),
            b'x' => self.start_tag_in(&["xmp"]),
            _ => false,
        };
        if raw {
            let name = self.buf[self.data.start..self.data.end].to_ascii_lowercase();
            self.raw_tag = [
                "iframe",
                "noembed",
                "noframes",
                "noscript",
                "plaintext",
                "script",
                "style",
                "textarea",
                "title",
                "xmp",
            ]
            .into_iter()
            .find(|s| s.as_bytes() == name)
            .unwrap_or("");
        }
        let n_attrs = self.attr.len();
        if !self.eof
            && self.buf[self.raw.end - 2] == b'/'
            && (n_attrs == 0 || self.raw.end - 2 != self.attr[n_attrs - 1][1].end.wrapping_sub(1))
        {
            return TokenType::SelfClosingTag;
        }
        TokenType::StartTag
    }

    fn read_tag(&mut self, save_attr: bool) {
        self.attr.clear();
        self.n_attr_returned = 0;
        self.read_tag_name();
        self.skip_white_space();
        if self.eof {
            return;
        }
        loop {
            let c = self.read_byte();
            if self.eof || c == b'>' {
                break;
            }
            self.raw.end -= 1;
            self.read_tag_attr_key();
            self.read_tag_attr_val();
            if save_attr && self.pending_attr[0].start != self.pending_attr[0].end {
                self.attr.push(self.pending_attr);
            }
            self.skip_white_space();
            if self.eof {
                break;
            }
        }
    }

    fn read_tag_name(&mut self) {
        self.data.start = self.raw.end - 1;
        loop {
            let c = self.read_byte();
            if self.eof {
                self.data.end = self.raw.end;
                return;
            }
            match c {
                b' ' | b'\n' | b'\r' | b'\t' | 0x0c => {
                    self.data.end = self.raw.end - 1;
                    return;
                }
                b'/' | b'>' => {
                    self.raw.end -= 1;
                    self.data.end = self.raw.end;
                    return;
                }
                _ => {}
            }
        }
    }

    fn read_tag_attr_key(&mut self) {
        self.pending_attr[0].start = self.raw.end;
        loop {
            let c = self.read_byte();
            if self.eof {
                self.pending_attr[0].end = self.raw.end;
                return;
            }
            match c {
                b'=' if self.pending_attr[0].start + 1 == self.raw.end => continue,
                b'=' | b' ' | b'\n' | b'\r' | b'\t' | 0x0c | b'/' | b'>' => {
                    self.raw.end -= 1;
                    self.pending_attr[0].end = self.raw.end;
                    return;
                }
                _ => {}
            }
        }
    }

    fn read_tag_attr_val(&mut self) {
        self.pending_attr[1].start = self.raw.end;
        self.pending_attr[1].end = self.raw.end;
        self.skip_white_space();
        if self.eof {
            return;
        }
        let c = self.read_byte();
        if self.eof {
            return;
        }
        if c == b'/' {
            return;
        }
        if c != b'=' {
            self.raw.end -= 1;
            return;
        }
        self.skip_white_space();
        if self.eof {
            return;
        }
        let quote = self.read_byte();
        if self.eof {
            return;
        }
        match quote {
            b'>' => self.raw.end -= 1,
            b'\'' | b'"' => {
                self.pending_attr[1].start = self.raw.end;
                loop {
                    let c = self.read_byte();
                    if self.eof {
                        self.pending_attr[1].end = self.raw.end;
                        return;
                    }
                    if c == quote {
                        self.pending_attr[1].end = self.raw.end - 1;
                        return;
                    }
                }
            }
            _ => {
                self.pending_attr[1].start = self.raw.end - 1;
                loop {
                    let c = self.read_byte();
                    if self.eof {
                        self.pending_attr[1].end = self.raw.end;
                        return;
                    }
                    if is_space(c) {
                        self.pending_attr[1].end = self.raw.end - 1;
                        return;
                    }
                    if c == b'>' {
                        self.raw.end -= 1;
                        self.pending_attr[1].end = self.raw.end;
                        return;
                    }
                }
            }
        }
    }

    pub fn next(&mut self) -> TokenType {
        self.raw.start = self.raw.end;
        self.data.start = self.raw.end;
        self.data.end = self.raw.end;
        if self.eof {
            self.tt = TokenType::Error;
            return self.tt;
        }
        if !self.raw_tag.is_empty() {
            if self.raw_tag == "plaintext" {
                while !self.eof {
                    self.read_byte();
                }
                self.data.end = self.raw.end;
                self.text_is_raw = true;
            } else {
                self.read_raw_or_rcdata();
            }
            if self.data.end > self.data.start {
                self.tt = TokenType::Text;
                self.convert_nul = true;
                return self.tt;
            }
        }
        self.text_is_raw = false;
        self.convert_nul = false;

        loop {
            let c = self.read_byte();
            if self.failed() {
                break;
            }
            if c != b'<' {
                continue;
            }
            let c = self.read_byte();
            if self.failed() {
                break;
            }
            let token_type = if is_alpha(c) {
                TokenType::StartTag
            } else if c == b'/' {
                TokenType::EndTag
            } else if c == b'!' || c == b'?' {
                TokenType::Comment
            } else {
                self.raw.end -= 1;
                continue;
            };
            let x = self.raw.end - 2;
            if self.raw.start < x {
                self.raw.end = x;
                self.data.end = x;
                self.tt = TokenType::Text;
                return self.tt;
            }
            match token_type {
                TokenType::StartTag => {
                    self.tt = self.read_start_tag();
                    return self.tt;
                }
                TokenType::EndTag => {
                    let c = self.read_byte();
                    if self.failed() {
                        break;
                    }
                    if c == b'>' {
                        self.tt = TokenType::Comment;
                        return self.tt;
                    }
                    if is_alpha(c) {
                        self.read_tag(false);
                        self.tt = if self.failed() {
                            TokenType::Error
                        } else {
                            TokenType::EndTag
                        };
                        return self.tt;
                    }
                    self.raw.end -= 1;
                    self.read_until_close_angle();
                    self.tt = TokenType::Comment;
                    return self.tt;
                }
                _ => {
                    if c == b'!' {
                        self.tt = self.read_markup_declaration();
                        return self.tt;
                    }
                    self.raw.end -= 1;
                    self.read_until_close_angle();
                    self.tt = TokenType::Comment;
                    return self.tt;
                }
            }
        }
        if self.raw.start < self.raw.end {
            self.data.end = self.raw.end;
            self.tt = TokenType::Text;
            return self.tt;
        }
        self.tt = TokenType::Error;
        self.tt
    }

    fn text(&mut self) -> Vec<u8> {
        let s = self.buf[self.data.start..self.data.end].to_vec();
        self.data.start = self.raw.end;
        self.data.end = self.raw.end;
        let mut s = convert_newlines(&s);
        if (self.convert_nul || self.tt == TokenType::Comment) && s.contains(&0) {
            let mut r = Vec::with_capacity(s.len());
            for &b in &s {
                if b == 0 {
                    r.extend_from_slice("\u{FFFD}".as_bytes());
                } else {
                    r.push(b);
                }
            }
            s = r;
        }
        if !self.text_is_raw {
            s = unescape(&s, false);
        }
        s
    }

    /// The current token, with decoded data and attributes.
    pub fn token(&mut self) -> Token {
        let mut t = Token {
            ty: self.tt,
            atom: String::new(),
            data: String::new(),
            attr: Vec::new(),
        };
        match self.tt {
            TokenType::Text | TokenType::Comment | TokenType::Doctype => {
                t.data = lossy(self.text());
            }
            TokenType::StartTag | TokenType::SelfClosingTag | TokenType::EndTag => {
                let name = if self.data.start < self.data.end {
                    let s = self.buf[self.data.start..self.data.end].to_ascii_lowercase();
                    self.data.start = self.raw.end;
                    self.data.end = self.raw.end;
                    s
                } else {
                    Vec::new()
                };
                let attr_ok = matches!(self.tt, TokenType::StartTag | TokenType::SelfClosingTag);
                if attr_ok {
                    for x in &self.attr[self.n_attr_returned..] {
                        let key = self.buf[x[0].start..x[0].end].to_ascii_lowercase();
                        let val =
                            unescape(&convert_newlines(&self.buf[x[1].start..x[1].end]), true);
                        t.attr.push(Attribute {
                            namespace: String::new(),
                            key: lossy(key),
                            val: lossy(val),
                        });
                    }
                    self.n_attr_returned = self.attr.len();
                }
                t.data = lossy(name);
                t.atom = atom_of(&t.data);
            }
            TokenType::Error => {}
        }
        t
    }
}
