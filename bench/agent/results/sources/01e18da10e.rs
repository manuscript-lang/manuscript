use std::fmt::Write as FmtWrite;
use std::io::{self, Read, Write};

type Set = [bool; 256];
type Caps = Vec<Option<(usize, usize)>>;
type PResult<T> = Result<T, &'static str>;

#[derive(Clone, Copy)]
struct Flags {
    i: bool,
    m: bool,
    s: bool,
}

enum Node {
    Empty,
    Set(Box<Set>),
    Start,
    End,
    WordB(bool),
    Group(Option<usize>, Box<Node>),
    Concat(Vec<Node>),
    Alt(Vec<Node>),
    Repeat {
        node: Box<Node>,
        min: u32,
        max: Option<u32>,
        greedy: bool,
    },
    Look {
        node: Box<Node>,
        neg: bool,
    },
    BackNum(usize),
    BackName(String),
}

struct Compiled {
    root: Node,
    ngroups: usize,
    names: Vec<(String, usize)>,
    flags: Flags,
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn hexval(c: u8) -> Option<u8> {
    (c as char).to_digit(16).map(|d| d as u8)
}

fn shorthand(c: u8) -> Option<Set> {
    let lower = c.to_ascii_lowercase();
    if !matches!(lower, b'd' | b'w' | b's') {
        return None;
    }
    let mut set = [false; 256];
    for (b, slot) in set.iter_mut().enumerate() {
        let x = b as u8;
        *slot = match lower {
            b'd' => x.is_ascii_digit(),
            b'w' => is_word(x),
            _ => matches!(x, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c),
        };
    }
    if c.is_ascii_uppercase() {
        for v in set.iter_mut() {
            *v = !*v;
        }
    }
    Some(set)
}

fn simple_escape(c: u8) -> Option<u8> {
    match c {
        b'n' => Some(10),
        b't' => Some(9),
        b'r' => Some(13),
        _ => None,
    }
}

enum ClassAtom {
    Byte(u8),
    Set(Set),
}

fn digits(p: &[u8], i: &mut usize) -> Option<u64> {
    let start = *i;
    let mut v: u64 = 0;
    while let Some(&c) = p.get(*i) {
        if c.is_ascii_digit() {
            v = v.saturating_mul(10).saturating_add((c - b'0') as u64);
            *i += 1;
        } else {
            break;
        }
    }
    if *i == start {
        None
    } else {
        Some(v)
    }
}

struct Parser<'a> {
    p: &'a [u8],
    pos: usize,
    flags: Flags,
    ngroups: usize,
    names: Vec<(String, usize)>,
    name_refs: Vec<String>,
    max_back: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<u8> {
        self.p.get(self.pos).copied()
    }

    fn peek_at(&self, off: usize) -> Option<u8> {
        self.p.get(self.pos + off).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let c = self.peek()?;
        self.pos += 1;
        Some(c)
    }

    fn byte_node(&self, b: u8) -> Node {
        let mut set = [false; 256];
        set[b as usize] = true;
        if self.flags.i && b.is_ascii_alphabetic() {
            set[b.to_ascii_lowercase() as usize] = true;
            set[b.to_ascii_uppercase() as usize] = true;
        }
        Node::Set(Box::new(set))
    }

    fn close(&mut self) -> PResult<()> {
        if self.peek() == Some(b')') {
            self.pos += 1;
            Ok(())
        } else {
            Err("unmatched (")
        }
    }

    fn parse_alt(&mut self) -> PResult<Node> {
        let mut alts = vec![self.parse_concat()?];
        while self.peek() == Some(b'|') {
            self.pos += 1;
            alts.push(self.parse_concat()?);
        }
        Ok(if alts.len() == 1 {
            alts.pop().unwrap()
        } else {
            Node::Alt(alts)
        })
    }

    fn parse_concat(&mut self) -> PResult<Node> {
        let mut items = Vec::new();
        while !matches!(self.peek(), None | Some(b'|') | Some(b')')) {
            let (mut node, quantifiable) = self.parse_atom()?;
            let mut quantified = false;
            while let Some((min, max, greedy)) = self.try_quantifier() {
                if quantified || !quantifiable {
                    return Err("nothing to repeat");
                }
                if min > 1000 || max.map_or(false, |m| m > 1000 || m < min) {
                    return Err("bad repeat");
                }
                node = Node::Repeat {
                    node: Box::new(node),
                    min: min as u32,
                    max: max.map(|m| m as u32),
                    greedy,
                };
                quantified = true;
            }
            items.push(node);
        }
        Ok(match items.len() {
            0 => Node::Empty,
            1 => items.pop().unwrap(),
            _ => Node::Concat(items),
        })
    }

    fn try_quantifier(&mut self) -> Option<(u64, Option<u64>, bool)> {
        let (min, max) = match self.peek()? {
            b'*' => {
                self.pos += 1;
                (0, None)
            }
            b'+' => {
                self.pos += 1;
                (1, None)
            }
            b'?' => {
                self.pos += 1;
                (0, Some(1))
            }
            b'{' => self.brace()?,
            _ => return None,
        };
        let greedy = if self.peek() == Some(b'?') {
            self.pos += 1;
            false
        } else {
            true
        };
        Some((min, max, greedy))
    }

    fn brace(&mut self) -> Option<(u64, Option<u64>)> {
        let mut i = self.pos + 1;
        let min = digits(self.p, &mut i)?;
        let max = if self.p.get(i) == Some(&b',') {
            i += 1;
            if self.p.get(i) == Some(&b'}') {
                None
            } else {
                Some(digits(self.p, &mut i)?)
            }
        } else {
            Some(min)
        };
        if self.p.get(i) != Some(&b'}') {
            return None;
        }
        self.pos = i + 1;
        Some((min, max))
    }

    /// Returns the atom and whether it may be quantified.
    fn parse_atom(&mut self) -> PResult<(Node, bool)> {
        let c = self.bump().unwrap();
        Ok(match c {
            b'(' => return self.parse_group(),
            b'[' => (Node::Set(Box::new(self.parse_class()?)), true),
            b'.' => {
                let mut set = [true; 256];
                if !self.flags.s {
                    set[b'\n' as usize] = false;
                }
                (Node::Set(Box::new(set)), true)
            }
            b'^' => (Node::Start, false),
            b'$' => (Node::End, false),
            b'\\' => return self.parse_escape(),
            b'*' | b'+' | b'?' => return Err("nothing to repeat"),
            _ => (self.byte_node(c), true),
        })
    }

    fn hex2(&mut self) -> Option<u8> {
        let h = hexval(*self.p.get(self.pos)?)?;
        let l = hexval(*self.p.get(self.pos + 1)?)?;
        self.pos += 2;
        Some(h * 16 + l)
    }

    fn read_name(&mut self) -> Option<String> {
        let start = self.pos;
        match self.peek() {
            Some(c) if c.is_ascii_alphabetic() || c == b'_' => {}
            _ => return None,
        }
        while let Some(c) = self.peek() {
            if c.is_ascii_alphanumeric() || c == b'_' {
                self.pos += 1;
            } else {
                break;
            }
        }
        let name = String::from_utf8_lossy(&self.p[start..self.pos]).into_owned();
        if self.peek() == Some(b'>') {
            self.pos += 1;
            Some(name)
        } else {
            None
        }
    }

    fn parse_escape(&mut self) -> PResult<(Node, bool)> {
        let c = self.bump().ok_or("bad escape")?;
        if let Some(set) = shorthand(c) {
            return Ok((Node::Set(Box::new(set)), true));
        }
        if let Some(b) = simple_escape(c) {
            return Ok((self.byte_node(b), true));
        }
        match c {
            b'x' => {
                let b = self.hex2().ok_or("bad escape")?;
                Ok((self.byte_node(b), true))
            }
            b'b' => Ok((Node::WordB(true), false)),
            b'B' => Ok((Node::WordB(false), false)),
            b'1'..=b'9' => {
                let n = (c - b'0') as usize;
                self.max_back = self.max_back.max(n);
                Ok((Node::BackNum(n), true))
            }
            b'k' => {
                if self.peek() != Some(b'<') {
                    return Err("bad escape");
                }
                self.pos += 1;
                let name = self.read_name().ok_or("bad escape")?;
                self.name_refs.push(name.clone());
                Ok((Node::BackName(name), true))
            }
            _ if c < 0x80 && !c.is_ascii_alphanumeric() => Ok((self.byte_node(c), true)),
            _ => Err("bad escape"),
        }
    }

    fn class_atom(&mut self) -> PResult<ClassAtom> {
        let c = self.bump().ok_or("unterminated class")?;
        if c != b'\\' {
            return Ok(ClassAtom::Byte(c));
        }
        let e = self.bump().ok_or("bad escape")?;
        if let Some(s) = shorthand(e) {
            return Ok(ClassAtom::Set(s));
        }
        if let Some(b) = simple_escape(e) {
            return Ok(ClassAtom::Byte(b));
        }
        match e {
            b'x' => Ok(ClassAtom::Byte(self.hex2().ok_or("bad escape")?)),
            _ if e < 0x80 && !e.is_ascii_alphanumeric() => Ok(ClassAtom::Byte(e)),
            _ => Err("bad escape"),
        }
    }

    fn parse_class(&mut self) -> PResult<Set> {
        let neg = if self.peek() == Some(b'^') {
            self.pos += 1;
            true
        } else {
            false
        };
        let mut set = [false; 256];
        let mut first = true;
        let mut after_range = false;
        loop {
            let c = self.peek().ok_or("unterminated class")?;
            if c == b']' && !first {
                self.pos += 1;
                break;
            }
            first = false;
            match self.class_atom()? {
                ClassAtom::Byte(b) => {
                    let dash_follows =
                        self.peek() == Some(b'-') && matches!(self.peek_at(1), Some(x) if x != b']');
                    if !(after_range && b == b'-') && dash_follows {
                        self.pos += 1;
                        match self.class_atom()? {
                            ClassAtom::Byte(e) => {
                                if e < b {
                                    return Err("bad range");
                                }
                                for x in b..=e {
                                    set[x as usize] = true;
                                }
                            }
                            ClassAtom::Set(_) => return Err("bad range"),
                        }
                        after_range = true;
                    } else {
                        set[b as usize] = true;
                        after_range = false;
                    }
                }
                ClassAtom::Set(s) => {
                    if self.peek() == Some(b'-')
                        && matches!(self.peek_at(1), Some(x) if x != b']')
                    {
                        return Err("bad range");
                    }
                    for i in 0..256 {
                        set[i] |= s[i];
                    }
                    after_range = false;
                }
            }
        }
        if self.flags.i {
            for b in b'a'..=b'z' {
                let u = b.to_ascii_uppercase();
                if set[b as usize] || set[u as usize] {
                    set[b as usize] = true;
                    set[u as usize] = true;
                }
            }
        }
        if neg {
            for x in set.iter_mut() {
                *x = !*x;
            }
        }
        Ok(set)
    }

    fn parse_group(&mut self) -> PResult<(Node, bool)> {
        if self.peek() == Some(b'?') {
            self.pos += 1;
            match self.bump() {
                Some(b':') => {
                    let body = self.parse_alt()?;
                    self.close()?;
                    Ok((Node::Group(None, Box::new(body)), true))
                }
                Some(c @ (b'=' | b'!')) => {
                    let body = self.parse_alt()?;
                    self.close()?;
                    Ok((
                        Node::Look {
                            node: Box::new(body),
                            neg: c == b'!',
                        },
                        false,
                    ))
                }
                Some(b'<') => {
                    let name = self.read_name().ok_or("bad group")?;
                    if self.names.iter().any(|(n, _)| *n == name) {
                        return Err("duplicate group name");
                    }
                    self.ngroups += 1;
                    let idx = self.ngroups;
                    self.names.push((name, idx));
                    let body = self.parse_alt()?;
                    self.close()?;
                    Ok((Node::Group(Some(idx), Box::new(body)), true))
                }
                _ => Err("bad group"),
            }
        } else {
            self.ngroups += 1;
            let idx = self.ngroups;
            let body = self.parse_alt()?;
            self.close()?;
            Ok((Node::Group(Some(idx), Box::new(body)), true))
        }
    }
}

fn compile(p: &[u8]) -> PResult<Compiled> {
    let mut flags = Flags {
        i: false,
        m: false,
        s: false,
    };
    let mut pos = 0;
    if p.starts_with(b"(?") {
        let mut j = 2;
        let mut f = flags;
        while j < p.len() && matches!(p[j], b'i' | b'm' | b's') {
            match p[j] {
                b'i' => f.i = true,
                b'm' => f.m = true,
                _ => f.s = true,
            }
            j += 1;
        }
        if j > 2 && p.get(j) == Some(&b')') {
            flags = f;
            pos = j + 1;
        }
    }
    let mut parser = Parser {
        p,
        pos,
        flags,
        ngroups: 0,
        names: Vec::new(),
        name_refs: Vec::new(),
        max_back: 0,
    };
    let root = parser.parse_alt()?;
    if parser.pos < p.len() {
        return Err("unmatched )");
    }
    if parser.max_back > parser.ngroups {
        return Err("bad backreference");
    }
    for r in &parser.name_refs {
        if !parser.names.iter().any(|(n, _)| n == r) {
            return Err("bad backreference");
        }
    }
    Ok(Compiled {
        root,
        ngroups: parser.ngroups,
        names: parser.names,
        flags,
    })
}

struct Matcher<'a> {
    s: &'a [u8],
    flags: Flags,
    caps: Caps,
    names: &'a [(String, usize)],
}

impl<'a> Matcher<'a> {
    fn m(&mut self, node: &Node, pos: usize, k: &mut dyn FnMut(&mut Matcher<'a>, usize) -> bool) -> bool {
        match node {
            Node::Empty => k(self, pos),
            Node::Set(set) => pos < self.s.len() && set[self.s[pos] as usize] && k(self, pos + 1),
            Node::Start => {
                let ok = pos == 0 || (self.flags.m && self.s[pos - 1] == b'\n');
                ok && k(self, pos)
            }
            Node::End => {
                let ok = pos == self.s.len() || (self.flags.m && self.s[pos] == b'\n');
                ok && k(self, pos)
            }
            Node::WordB(want) => {
                let before = pos > 0 && is_word(self.s[pos - 1]);
                let after = pos < self.s.len() && is_word(self.s[pos]);
                ((before != after) == *want) && k(self, pos)
            }
            Node::Group(idx, body) => match idx {
                None => self.m(body, pos, k),
                Some(g) => {
                    let g = *g;
                    self.m(body, pos, &mut |me: &mut Matcher<'a>, p: usize| {
                        let old = me.caps[g];
                        me.caps[g] = Some((pos, p));
                        if k(me, p) {
                            return true;
                        }
                        me.caps[g] = old;
                        false
                    })
                }
            },
            Node::Concat(items) => self.m_seq(items, pos, k),
            Node::Alt(alts) => {
                for a in alts {
                    if self.m(a, pos, k) {
                        return true;
                    }
                }
                false
            }
            Node::Repeat {
                node: body,
                min,
                max,
                greedy,
            } => self.m_rep(body, *min, *max, *greedy, 0, pos, k),
            Node::Look { node: body, neg } => {
                let snap = self.caps.clone();
                let matched = self.m(body, pos, &mut |_, _| true);
                if *neg {
                    self.caps = snap;
                    !matched && k(self, pos)
                } else {
                    if !matched {
                        return false;
                    }
                    if k(self, pos) {
                        return true;
                    }
                    self.caps = snap;
                    false
                }
            }
            Node::BackNum(n) => self.backref(*n, pos, k),
            Node::BackName(name) => {
                let idx = self
                    .names
                    .iter()
                    .find(|(n, _)| n == name)
                    .map(|x| x.1)
                    .unwrap_or(0);
                self.backref(idx, pos, k)
            }
        }
    }

    fn backref(&mut self, g: usize, pos: usize, k: &mut dyn FnMut(&mut Matcher<'a>, usize) -> bool) -> bool {
        let Some((s, e)) = self.caps[g] else {
            return false;
        };
        let len = e - s;
        if pos + len > self.s.len() {
            return false;
        }
        let ok = (0..len).all(|i| {
            let a = self.s[s + i];
            let b = self.s[pos + i];
            if self.flags.i {
                a.eq_ignore_ascii_case(&b)
            } else {
                a == b
            }
        });
        ok && k(self, pos + len)
    }

    fn m_seq(&mut self, items: &[Node], pos: usize, k: &mut dyn FnMut(&mut Matcher<'a>, usize) -> bool) -> bool {
        match items.split_first() {
            None => k(self, pos),
            Some((first, rest)) => self.m(first, pos, &mut |me: &mut Matcher<'a>, p: usize| {
                me.m_seq(rest, p, &mut *k)
            }),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn m_rep(
        &mut self,
        node: &Node,
        min: u32,
        max: Option<u32>,
        greedy: bool,
        count: u32,
        pos: usize,
        k: &mut dyn FnMut(&mut Matcher<'a>, usize) -> bool,
    ) -> bool {
        if count < min {
            return self.m(node, pos, &mut |me: &mut Matcher<'a>, p: usize| {
                if p == pos && count + 1 == min {
                    k(me, p)
                } else {
                    me.m_rep(node, min, max, greedy, count + 1, p, &mut *k)
                }
            });
        }
        let more = max.map_or(true, |mx| count < mx);
        if greedy {
            if more
                && self.m(node, pos, &mut |me: &mut Matcher<'a>, p: usize| {
                    if p == pos {
                        k(me, p)
                    } else {
                        me.m_rep(node, min, max, greedy, count + 1, p, &mut *k)
                    }
                })
            {
                return true;
            }
            k(self, pos)
        } else {
            if k(self, pos) {
                return true;
            }
            more && self.m(node, pos, &mut |me: &mut Matcher<'a>, p: usize| {
                if p == pos {
                    k(me, p)
                } else {
                    me.m_rep(node, min, max, greedy, count + 1, p, &mut *k)
                }
            })
        }
    }
}

/// Leftmost match at or after `from`. With `full`, only start 0 and the match must end at the subject end.
fn search(c: &Compiled, s: &[u8], from: usize, full: bool) -> Option<Caps> {
    let n = s.len();
    let last = if full { 0 } else { n };
    if full && from > 0 {
        return None;
    }
    for start in from..=last {
        let mut m = Matcher {
            s,
            flags: c.flags,
            caps: vec![None; c.ngroups + 1],
            names: &c.names,
        };
        let mut end = 0usize;
        let ok = m.m(&c.root, start, &mut |_: &mut Matcher, p: usize| {
            if full && p != n {
                return false;
            }
            end = p;
            true
        });
        if ok {
            let mut caps = m.caps;
            caps[0] = Some((start, end));
            return Some(caps);
        }
    }
    None
}

fn find_all(c: &Compiled, s: &[u8]) -> Vec<Caps> {
    let mut res = Vec::new();
    let mut pos = 0;
    while pos <= s.len() {
        match search(c, s, pos, false) {
            None => break,
            Some(caps) => {
                let (st, e) = caps[0].unwrap();
                pos = if e > st { e } else { e + 1 };
                res.push(caps);
            }
        }
    }
    res
}

fn unescape(b: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] != b'\\' {
            out.push(b[i]);
            i += 1;
            continue;
        }
        i += 1;
        let c = *b.get(i)?;
        i += 1;
        match c {
            b'n' => out.push(10),
            b't' => out.push(9),
            b'\\' => out.push(b'\\'),
            b'x' => {
                let h = hexval(*b.get(i)?)?;
                let l = hexval(*b.get(i + 1)?)?;
                out.push(h * 16 + l);
                i += 2;
            }
            _ => return None,
        }
    }
    Some(out)
}

fn quoted(b: &[u8]) -> String {
    let mut s = String::from("\"");
    for &c in b {
        match c {
            b'\\' => s.push_str("\\\\"),
            b'"' => s.push_str("\\\""),
            b'\n' => s.push_str("\\n"),
            b'\t' => s.push_str("\\t"),
            b'\r' => s.push_str("\\r"),
            0x20..=0x7e => s.push(c as char),
            _ => {
                let _ = write!(s, "\\x{:02x}", c);
            }
        }
    }
    s.push('"');
    s
}

fn expand(rep: &[u8], s: &[u8], caps: &Caps, c: &Compiled) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < rep.len() {
        if rep[i] != b'$' {
            out.push(rep[i]);
            i += 1;
            continue;
        }
        if i + 1 >= rep.len() {
            out.push(b'$');
            i += 1;
            continue;
        }
        let d = rep[i + 1];
        match d {
            b'0'..=b'9' => {
                let g = (d - b'0') as usize;
                if g > c.ngroups {
                    return None;
                }
                if let Some((a, e)) = caps[g] {
                    out.extend_from_slice(&s[a..e]);
                }
                i += 2;
            }
            b'$' => {
                out.push(b'$');
                i += 2;
            }
            b'{' => {
                let close = rep[i + 2..].iter().position(|&x| x == b'}')? + i + 2;
                let name = &rep[i + 2..close];
                let idx = c.names.iter().find(|(n, _)| n.as_bytes() == name)?.1;
                if let Some((a, e)) = caps[idx] {
                    out.extend_from_slice(&s[a..e]);
                }
                i = close + 1;
            }
            _ => {
                out.push(b'$');
                i += 1;
            }
        }
    }
    Some(out)
}

fn group_lines(c: &Compiled, s: &[u8], caps: &Caps, out: &mut String) {
    for g in 0..=c.ngroups {
        let named = c.names.iter().find(|(_, i)| *i == g);
        let label = match named {
            Some((n, _)) => format!("{} ({})", g, n),
            None => g.to_string(),
        };
        match caps[g] {
            Some((a, e)) => {
                let _ = writeln!(out, "{}: {}..{} {}", label, a, e, quoted(&s[a..e]));
            }
            None => {
                let _ = writeln!(out, "{}: unset", label);
            }
        }
    }
}

fn bad(out: &mut String) {
    out.push_str("error: bad command\n");
}

fn process(line: &[u8], out: &mut String) {
    let fields: Vec<&[u8]> = line.split(|&b| b == b'\t').collect();
    let cmd = fields[0];
    let want = match cmd {
        b"test" | b"match" | b"full" | b"find-all" | b"split" => 3,
        b"replace" => 4,
        _ => return bad(out),
    };
    if fields.len() != want {
        return bad(out);
    }
    let subject = match unescape(fields[2]) {
        Some(v) => v,
        None => return bad(out),
    };
    let repl = if want == 4 {
        match unescape(fields[3]) {
            Some(v) => v,
            None => return bad(out),
        }
    } else {
        Vec::new()
    };
    let pat = match compile(fields[1]) {
        Ok(c) => c,
        Err(e) => {
            let _ = writeln!(out, "error: {}", e);
            return;
        }
    };
    let s = &subject[..];
    match cmd {
        b"test" => {
            out.push_str(if search(&pat, s, 0, false).is_some() {
                "true\n"
            } else {
                "false\n"
            });
        }
        b"match" | b"full" => match search(&pat, s, 0, cmd == b"full") {
            None => out.push_str("no match\n"),
            Some(caps) => group_lines(&pat, s, &caps, out),
        },
        b"find-all" => {
            let ms = find_all(&pat, s);
            for caps in &ms {
                let (a, e) = caps[0].unwrap();
                let _ = writeln!(out, "{}..{} {}", a, e, quoted(&s[a..e]));
            }
            let _ = writeln!(out, "({} matches)", ms.len());
        }
        b"split" => {
            let ms = find_all(&pat, s);
            let mut pieces: Vec<&[u8]> = Vec::new();
            let mut prev = 0;
            for caps in &ms {
                let (a, e) = caps[0].unwrap();
                if a == e {
                    continue;
                }
                pieces.push(&s[prev..a]);
                prev = e;
            }
            pieces.push(&s[prev..]);
            for p in &pieces {
                let _ = writeln!(out, "{}", quoted(p));
            }
            let _ = writeln!(out, "({} pieces)", pieces.len());
        }
        _ => {
            // replace
            let ms = find_all(&pat, s);
            let mut res: Vec<u8> = Vec::new();
            let mut prev = 0;
            for caps in &ms {
                let (a, e) = caps[0].unwrap();
                res.extend_from_slice(&s[prev..a]);
                match expand(&repl, s, caps, &pat) {
                    Some(x) => res.extend_from_slice(&x),
                    None => {
                        out.push_str("error: bad replacement\n");
                        return;
                    }
                }
                prev = e;
            }
            res.extend_from_slice(&s[prev..]);
            let _ = writeln!(out, "{}", quoted(&res));
        }
    }
}

fn run() {
    let mut input = Vec::new();
    let _ = io::stdin().read_to_end(&mut input);
    let mut out = String::new();
    for line in input.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }
        process(line, &mut out);
    }
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(out.as_bytes());
    let _ = lock.flush();
}

fn main() {
    // Deeply backtracking matches recurse once per consumed byte; use a large stack.
    let h = std::thread::Builder::new()
        .stack_size(512 << 20)
        .spawn(run)
        .expect("spawn");
    let _ = h.join();
}
