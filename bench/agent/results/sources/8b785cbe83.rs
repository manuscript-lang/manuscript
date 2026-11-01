use std::io::{self, Read, Write};

// Sentinel for a two-space hard break inside paragraph text (input is ASCII, so this never collides).
const SENT: char = '\u{E000}';

fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            _ => o.push(c),
        }
    }
    o
}

fn indent_of(s: &str) -> usize {
    s.bytes().take_while(|&b| b == b' ').count()
}

fn is_blank(s: &str) -> bool {
    s.bytes().all(|b| b == b' ')
}

fn strip_up_to(s: &str, k: usize) -> String {
    let m = indent_of(s).min(k);
    s[m..].to_string()
}

fn safe_tail(s: &str, w: usize) -> String {
    if s.len() > w {
        s[w..].to_string()
    } else {
        String::new()
    }
}

// ---------- line classifiers ----------

struct Fence {
    ch: u8,
    len: usize,
    indent: usize,
    info: String,
}

fn fence_open(line: &str) -> Option<Fence> {
    let ind = indent_of(line);
    if ind > 3 {
        return None;
    }
    let s = &line[ind..];
    let b = s.as_bytes();
    if b.is_empty() {
        return None;
    }
    let ch = b[0];
    if ch != b'`' && ch != b'~' {
        return None;
    }
    let len = b.iter().take_while(|&&x| x == ch).count();
    if len < 3 {
        return None;
    }
    let info = s[len..].trim_matches(' ').to_string();
    if ch == b'`' && info.contains('`') {
        return None;
    }
    Some(Fence { ch, len, indent: ind, info })
}

fn is_fence_close(line: &str, ch: u8, len: usize) -> bool {
    let ind = indent_of(line);
    if ind > 3 {
        return false;
    }
    let s = line[ind..].as_bytes();
    let n = s.iter().take_while(|&&x| x == ch).count();
    n >= len && s[n..].iter().all(|&x| x == b' ')
}

fn atx(line: &str) -> Option<(usize, String)> {
    let ind = indent_of(line);
    if ind > 3 {
        return None;
    }
    let s = &line[ind..];
    let h = s.bytes().take_while(|&b| b == b'#').count();
    if h == 0 || h > 6 {
        return None;
    }
    if h < s.len() && s.as_bytes()[h] != b' ' {
        return None;
    }
    let mut c = s[h..].trim_matches(' ').to_string();
    let k = c.bytes().rev().take_while(|&b| b == b'#').count();
    if k > 0 {
        let l = c.len();
        if k == l || c.as_bytes()[l - k - 1] == b' ' {
            c.truncate(l - k);
            let t = c.trim_end_matches(' ').len();
            c.truncate(t);
        }
    }
    Some((h, c))
}

fn is_hr(line: &str) -> bool {
    if indent_of(line) > 3 {
        return false;
    }
    let t: Vec<u8> = line.bytes().filter(|&b| b != b' ').collect();
    t.len() >= 3 && (t[0] == b'-' || t[0] == b'*' || t[0] == b'_') && t.iter().all(|&b| b == t[0])
}

fn is_quote(line: &str) -> bool {
    let ind = indent_of(line);
    ind <= 3 && line.as_bytes().get(ind) == Some(&b'>')
}

#[derive(Clone, Copy)]
struct LMark {
    ordered: bool,
    num: u64,
    delim: u8,
    empty: bool,
    w: usize,
}

fn list_marker(line: &str) -> Option<LMark> {
    let ind = indent_of(line);
    if ind > 3 {
        return None;
    }
    let b = line.as_bytes();
    let mut p = ind;
    let (ordered, num, delim) = if p < b.len() && matches!(b[p], b'-' | b'*' | b'+') {
        let d = b[p];
        p += 1;
        (false, 0, d)
    } else {
        let d = b[p..].iter().take_while(|x| x.is_ascii_digit()).count();
        if d == 0 || d > 9 {
            return None;
        }
        let num: u64 = line[p..p + d].parse().ok()?;
        p += d;
        if p < b.len() && (b[p] == b'.' || b[p] == b')') {
            let dl = b[p];
            p += 1;
            (true, num, dl)
        } else {
            return None;
        }
    };
    if p < b.len() && b[p] != b' ' {
        return None;
    }
    let m_end = p;
    let n = b[p..].iter().take_while(|&&x| x == b' ').count();
    let empty = p + n >= b.len();
    let w = if empty || n >= 5 { m_end + 1 } else { m_end + n };
    Some(LMark { ordered, num, delim, empty, w })
}

fn para_continues(line: &str) -> bool {
    if is_blank(line) {
        return false;
    }
    if fence_open(line).is_some() || atx(line).is_some() || is_hr(line) || is_quote(line) {
        return false;
    }
    if let Some(m) = list_marker(line) {
        if !m.empty && (!m.ordered || m.num == 1) {
            return false;
        }
    }
    true
}

fn ends_table(line: &str) -> bool {
    is_blank(line) || fence_open(line).is_some() || atx(line).is_some() || is_hr(line) || is_quote(line)
}

fn split_cells(line: &str) -> Vec<String> {
    let mut s = line.trim_matches(' ');
    if s.starts_with('|') {
        s = &s[1..];
    }
    if s.ends_with('|') && !s[..s.len() - 1].ends_with('\\') {
        s = &s[..s.len() - 1];
    }
    let b = s.as_bytes();
    let mut cells = Vec::new();
    let mut start = 0;
    for k in 0..b.len() {
        if b[k] == b'|' && !(k > 0 && b[k - 1] == b'\\') {
            cells.push(s[start..k].trim_matches(' ').to_string());
            start = k + 1;
        }
    }
    cells.push(s[start..].trim_matches(' ').to_string());
    cells
}

// Returns alignments if the line is a delimiter row.
fn delim_cells(line: &str) -> Option<Vec<Option<&'static str>>> {
    if !line.contains('|') {
        return None;
    }
    let mut al = Vec::new();
    for c in split_cells(line) {
        let mut t = c.as_str();
        let left = t.starts_with(':');
        if left {
            t = &t[1..];
        }
        let right = t.ends_with(':');
        if right {
            t = &t[..t.len() - 1];
        }
        if t.is_empty() || !t.bytes().all(|x| x == b'-') {
            return None;
        }
        al.push(match (left, right) {
            (true, true) => Some("center"),
            (true, false) => Some("left"),
            (false, true) => Some("right"),
            _ => None,
        });
    }
    Some(al)
}

// ---------- block structure ----------

enum Block {
    Code { lang: Option<String>, lines: Vec<String> },
    Heading(usize, String),
    Hr,
    Quote(Vec<(Block, bool)>),
    List { ordered: bool, start: u64, loose: bool, items: Vec<Vec<(Block, bool)>> },
    Para(String),
    Table { aligns: Vec<Option<&'static str>>, head: Vec<String>, rows: Vec<Vec<String>> },
}

// Each block is paired with a flag: whether blank lines separated it from the previous block.
fn parse_blocks(lines: &[String]) -> Vec<(Block, bool)> {
    let mut out = Vec::new();
    let n = lines.len();
    let mut i = 0;
    let mut gap = false;
    while i < n {
        if is_blank(&lines[i]) {
            gap = true;
            i += 1;
            continue;
        }
        let (blk, ni) = parse_one(lines, i);
        out.push((blk, gap));
        gap = false;
        i = ni;
    }
    out
}

fn parse_one(lines: &[String], i: usize) -> (Block, usize) {
    let n = lines.len();
    let line = lines[i].as_str();

    // 1. fenced code
    if let Some(f) = fence_open(line) {
        let mut body = Vec::new();
        let mut j = i + 1;
        let mut closed = false;
        while j < n {
            if is_fence_close(&lines[j], f.ch, f.len) {
                closed = true;
                break;
            }
            body.push(strip_up_to(&lines[j], f.indent));
            j += 1;
        }
        let next = if closed { j + 1 } else { n };
        let lang = f.info.split(' ').next().filter(|w| !w.is_empty()).map(|w| w.to_string());
        return (Block::Code { lang, lines: body }, next);
    }

    // 2. ATX heading
    if let Some((h, c)) = atx(line) {
        return (Block::Heading(h, c), i + 1);
    }

    // 3. thematic break
    if is_hr(line) {
        return (Block::Hr, i + 1);
    }

    // 4. block quote
    if is_quote(line) {
        let mut inner = Vec::new();
        let mut j = i;
        while j < n && is_quote(&lines[j]) {
            let l = lines[j].as_str();
            let ind = indent_of(l);
            let mut rest = &l[ind + 1..];
            if rest.starts_with(' ') {
                rest = &rest[1..];
            }
            inner.push(rest.to_string());
            j += 1;
        }
        return (Block::Quote(parse_blocks(&inner)), j);
    }

    // 5. list
    if let Some(m0) = list_marker(line) {
        let mut items: Vec<Vec<(Block, bool)>> = Vec::new();
        let mut loose = false;
        let mut cur = i;
        let mut m = m0;
        loop {
            let w = m.w;
            let mut content = vec![safe_tail(&lines[cur], w)];
            let mut j = cur + 1;
            let mut last = cur;
            let mut pending = 0;
            while j < n {
                if is_blank(&lines[j]) {
                    pending += 1;
                    j += 1;
                    continue;
                }
                if indent_of(&lines[j]) >= w {
                    for _ in 0..pending {
                        content.push(String::new());
                    }
                    pending = 0;
                    content.push(safe_tail(&lines[j], w));
                    last = j;
                    j += 1;
                } else {
                    break;
                }
            }
            let children = parse_blocks(&content);
            if children.iter().skip(1).any(|(_, g)| *g) {
                loose = true;
            }
            items.push(children);

            let mut k = last + 1;
            while k < n && is_blank(&lines[k]) {
                k += 1;
            }
            let blank_between = k > last + 1;
            let next_ok = k < n
                && match list_marker(&lines[k]) {
                    Some(m2) => !is_hr(&lines[k]) && m2.ordered == m.ordered && m2.delim == m.delim,
                    None => false,
                };
            if !next_ok {
                return (
                    Block::List { ordered: m0.ordered, start: m0.num, loose, items },
                    last + 1,
                );
            }
            if blank_between {
                loose = true;
            }
            cur = k;
            m = list_marker(&lines[k]).unwrap();
        }
    }

    // 6. indented code
    if indent_of(line) >= 4 {
        let mut j = i;
        let mut last = i;
        while j < n && (is_blank(&lines[j]) || indent_of(&lines[j]) >= 4) {
            if !is_blank(&lines[j]) {
                last = j;
            }
            j += 1;
        }
        let body: Vec<String> = (i..=last).map(|k| strip_up_to(&lines[k], 4)).collect();
        return (Block::Code { lang: None, lines: body }, last + 1);
    }

    // 7. table
    if line.contains('|') && i + 1 < n {
        if let Some(al) = delim_cells(&lines[i + 1]) {
            let head = split_cells(line);
            if head.len() == al.len() {
                let mut rows = Vec::new();
                let mut j = i + 2;
                while j < n && !ends_table(&lines[j]) {
                    let mut c = split_cells(&lines[j]);
                    c.resize(al.len(), String::new());
                    rows.push(c);
                    j += 1;
                }
                return (Block::Table { aligns: al, head, rows }, j);
            }
        }
    }

    // 8. paragraph
    let mut j = i + 1;
    while j < n && para_continues(&lines[j]) {
        j += 1;
    }
    let mut text = String::new();
    for k in i..j {
        let s = lines[k].trim_start_matches(' ');
        let body = if k == j - 1 {
            s.trim_end_matches(' ').to_string()
        } else if s.ends_with("  ") {
            format!("{}{}", s.trim_end_matches(' '), SENT)
        } else {
            s.trim_end_matches(' ').to_string()
        };
        if k > i {
            text.push('\n');
        }
        text.push_str(&body);
    }
    (Block::Para(text), j)
}

// ---------- rendering of blocks ----------

fn render_blocks(blocks: &[(Block, bool)]) -> String {
    blocks.iter().map(|(b, _)| render_block(b)).collect()
}

fn render_block(b: &Block) -> String {
    match b {
        Block::Code { lang, lines } => {
            let mut s = match lang {
                Some(l) => format!("<pre><code class=\"language-{}\">", esc(l)),
                None => "<pre><code>".to_string(),
            };
            for l in lines {
                s += &esc(l);
                s.push('\n');
            }
            s += "</code></pre>\n";
            s
        }
        Block::Heading(h, c) => format!("<h{}>{}</h{}>\n", h, inline(c), h),
        Block::Hr => "<hr />\n".to_string(),
        Block::Quote(bs) => format!("<blockquote>\n{}</blockquote>\n", render_blocks(bs)),
        Block::List { ordered, start, loose, items } => {
            let tag = if *ordered { "ol" } else { "ul" };
            let mut s = if *ordered && *start != 1 {
                format!("<ol start=\"{}\">\n", start)
            } else {
                format!("<{}>\n", tag)
            };
            for it in items {
                s += "<li>";
                s += &render_item(it, !*loose);
                s += "</li>\n";
            }
            s += &format!("</{}>\n", tag);
            s
        }
        Block::Para(t) => format!("<p>{}</p>\n", inline(t)),
        Block::Table { aligns, head, rows } => {
            let cell = |tag: &str, al: Option<&str>, content: &str| -> String {
                match al {
                    Some(a) => format!("<{} align=\"{}\">{}</{}>\n", tag, a, inline(content), tag),
                    None => format!("<{}>{}</{}>\n", tag, inline(content), tag),
                }
            };
            let mut s = String::from("<table>\n<thead>\n<tr>\n");
            for (k, h) in head.iter().enumerate() {
                s += &cell("th", aligns[k], h);
            }
            s += "</tr>\n</thead>\n";
            if !rows.is_empty() {
                s += "<tbody>\n";
                for r in rows {
                    s += "<tr>\n";
                    for (k, c) in r.iter().enumerate() {
                        s += &cell("td", aligns[k], c);
                    }
                    s += "</tr>\n";
                }
                s += "</tbody>\n";
            }
            s += "</table>\n";
            s
        }
    }
}

fn render_item(children: &[(Block, bool)], tight: bool) -> String {
    let mut body = String::new();
    for (b, _) in children {
        if tight {
            if let Block::Para(t) = b {
                body += &inline(t);
                continue;
            }
        }
        if body.is_empty() || !body.ends_with('\n') {
            body.push('\n');
        }
        body += &render_block(b);
    }
    body
}

// ---------- inline processing ----------

enum Node {
    Text(String),
    Code(String),
    Soft,
    Hard,
    Delim { ch: char, count: usize, orig: usize, open: bool, close: bool },
    Opener { image: bool, active: bool },
    Em(Vec<Node>),
    Strong(Vec<Node>),
    Link { dest: String, title: Option<String>, kids: Vec<Node> },
    Image { dest: String, title: Option<String>, kids: Vec<Node> },
}

fn is_ws(c: Option<char>) -> bool {
    match c {
        None => true,
        Some(c) => c == ' ' || c == '\n' || c == SENT,
    }
}

fn is_punct(c: Option<char>) -> bool {
    c.map_or(false, |c| c.is_ascii_punctuation())
}

fn count_run(c: &[char], i: usize, ch: char) -> usize {
    c[i..].iter().take_while(|&&x| x == ch).count()
}

fn is_sp(c: char) -> bool {
    c == ' ' || c == '\n' || c == SENT
}

// `p0` is the index of '('. Returns (dest, title, index after ')').
fn parse_tail(c: &[char], p0: usize) -> Option<(String, Option<String>, usize)> {
    let n = c.len();
    let mut p = p0 + 1;
    while p < n && is_sp(c[p]) {
        p += 1;
    }
    let mut dest = String::new();
    if p < n && c[p] == '<' {
        p += 1;
        loop {
            if p >= n {
                return None;
            }
            let x = c[p];
            if x == '>' {
                p += 1;
                break;
            }
            if x == '\n' || x == SENT || x == '<' {
                return None;
            }
            if x == '\\' && p + 1 < n && c[p + 1].is_ascii_punctuation() {
                dest.push(c[p + 1]);
                p += 2;
                continue;
            }
            dest.push(x);
            p += 1;
        }
    } else {
        let mut depth = 0usize;
        while p < n {
            let x = c[p];
            if is_sp(x) {
                break;
            }
            if x == '\\' && p + 1 < n && c[p + 1].is_ascii_punctuation() {
                dest.push(c[p + 1]);
                p += 2;
                continue;
            }
            if x == '(' {
                depth += 1;
            } else if x == ')' {
                if depth == 0 {
                    break;
                }
                depth -= 1;
            }
            dest.push(x);
            p += 1;
        }
    }

    let q = p;
    while p < n && is_sp(c[p]) {
        p += 1;
    }
    let mut title = None;
    if p > q && p < n && c[p] == '"' {
        p += 1;
        let mut t = String::new();
        loop {
            if p >= n {
                return None;
            }
            let x = c[p];
            if x == '\\' && p + 1 < n && c[p + 1] == '"' {
                t.push('"');
                p += 2;
                continue;
            }
            if x == '"' {
                p += 1;
                break;
            }
            t.push(x);
            p += 1;
        }
        title = Some(t);
        while p < n && is_sp(c[p]) {
            p += 1;
        }
    }
    if p < n && c[p] == ')' {
        Some((dest, title, p + 1))
    } else {
        None
    }
}

// Delimiter info: (ch, remaining count, original count, can_open, can_close)
fn delim_info(n: &Node) -> Option<(char, usize, usize, bool, bool)> {
    match n {
        Node::Delim { ch, count, orig, open, close } => Some((*ch, *count, *orig, *open, *close)),
        _ => None,
    }
}

fn delim_count_mut(n: &mut Node) -> &mut usize {
    match n {
        Node::Delim { count, .. } => count,
        _ => panic!("not a delimiter"),
    }
}

// Converts a leftover delimiter run or bracket marker into literal text.
fn literal(n: Node) -> Node {
    match n {
        Node::Delim { ch, count, .. } => Node::Text(std::iter::repeat(ch).take(count).collect()),
        Node::Opener { image, .. } => Node::Text(if image { "![".into() } else { "[".into() }),
        other => other,
    }
}

fn lit_open(n: Node) -> Node {
    match n {
        Node::Opener { image, .. } => Node::Text(if image { "![".into() } else { "[".into() }),
        other => other,
    }
}

fn resolve(mut v: Vec<Node>) -> Vec<Node> {
    let mut ci = 0;
    while ci < v.len() {
        let (cch, ccount, corig, copen, cclose) = match delim_info(&v[ci]) {
            Some(d) if d.4 && d.1 > 0 => d,
            _ => {
                ci += 1;
                continue;
            }
        };
        let _ = cclose;
        let mut found = None;
        let mut oi = ci;
        while oi > 0 {
            oi -= 1;
            if let Some((ch, cnt, orig, open, close)) = delim_info(&v[oi]) {
                if ch == cch && open && cnt > 0 {
                    let skip = (close || copen) && (orig + corig) % 3 == 0 && !(orig % 3 == 0 && corig % 3 == 0);
                    if !skip {
                        found = Some(oi);
                        break;
                    }
                }
            }
        }
        let oi = match found {
            Some(x) => x,
            None => {
                ci += 1;
                continue;
            }
        };
        let ocount = delim_info(&v[oi]).unwrap().1;
        let use_n = if ocount >= 2 && ccount >= 2 { 2 } else { 1 };
        let inner: Vec<Node> = v.drain(oi + 1..ci).map(literal).collect();
        let emph = if use_n == 2 { Node::Strong(inner) } else { Node::Em(inner) };
        v.insert(oi + 1, emph);
        // closer is now at oi + 2
        *delim_count_mut(&mut v[oi]) -= use_n;
        *delim_count_mut(&mut v[oi + 2]) -= use_n;
        let mut e = oi + 1;
        if *delim_count_mut(&mut v[oi + 2]) == 0 {
            v.remove(oi + 2);
        }
        if *delim_count_mut(&mut v[oi]) == 0 {
            v.remove(oi);
            e -= 1;
        }
        ci = e + 1;
    }
    v
}

fn finish(v: Vec<Node>) -> Vec<Node> {
    resolve(v.into_iter().map(lit_open).collect()).into_iter().map(literal).collect()
}

// Handles a `]` at index i; returns the next scan index.
fn handle_close(nodes: &mut Vec<Node>, c: &[char], i: usize) -> usize {
    let n = c.len();
    let oi = match nodes.iter().rposition(|x| matches!(x, Node::Opener { .. })) {
        None => {
            nodes.push(Node::Text("]".into()));
            return i + 1;
        }
        Some(o) => o,
    };
    let (image, active) = match nodes[oi] {
        Node::Opener { image, active } => (image, active),
        _ => unreachable!(),
    };
    if !image && !active {
        nodes[oi] = Node::Text("[".into());
        nodes.push(Node::Text("]".into()));
        return i + 1;
    }
    let tail = if i + 1 < n && c[i + 1] == '(' { parse_tail(c, i + 1) } else { None };
    match tail {
        Some((dest, title, end)) => {
            let kids: Vec<Node> = nodes.drain(oi + 1..).collect();
            nodes.pop(); // the opener at oi
            let kids = finish(kids);
            if image {
                nodes.push(Node::Image { dest, title, kids });
            } else {
                nodes.push(Node::Link { dest, title, kids });
                for x in nodes.iter_mut() {
                    if let Node::Opener { image: false, active } = x {
                        *active = false;
                    }
                }
            }
            end
        }
        None => {
            nodes[oi] = Node::Text(if image { "![".into() } else { "[".into() });
            nodes.push(Node::Text("]".into()));
            i + 1
        }
    }
}

fn inline(s: &str) -> String {
    let c: Vec<char> = s.chars().collect();
    let n = c.len();
    let mut nodes: Vec<Node> = Vec::new();
    let mut i = 0;
    while i < n {
        let ch = c[i];
        match ch {
            '\\' => {
                if i + 1 < n && c[i + 1] == '\n' {
                    nodes.push(Node::Hard);
                    i += 2;
                } else if i + 1 < n && c[i + 1].is_ascii_punctuation() {
                    nodes.push(Node::Text(c[i + 1].to_string()));
                    i += 2;
                } else {
                    nodes.push(Node::Text("\\".into()));
                    i += 1;
                }
            }
            SENT => {
                nodes.push(Node::Hard);
                i += 1;
                if i < n && c[i] == '\n' {
                    i += 1;
                }
            }
            '\n' => {
                nodes.push(Node::Soft);
                i += 1;
            }
            '`' => {
                let run = count_run(&c, i, '`');
                let mut j = i + run;
                let mut found = None;
                while j < n {
                    if c[j] == '`' {
                        let m = count_run(&c, j, '`');
                        if m == run {
                            found = Some(j);
                            break;
                        }
                        j += m;
                    } else {
                        j += 1;
                    }
                }
                match found {
                    Some(j) => {
                        let mut content = String::new();
                        for &x in &c[i + run..j] {
                            match x {
                                SENT => {}
                                '\n' => content.push(' '),
                                _ => content.push(x),
                            }
                        }
                        if content.len() >= 2
                            && content.starts_with(' ')
                            && content.ends_with(' ')
                            && content.chars().any(|x| x != ' ')
                        {
                            content = content[1..content.len() - 1].to_string();
                        }
                        nodes.push(Node::Code(content));
                        i = j + run;
                    }
                    None => {
                        nodes.push(Node::Text("`".repeat(run)));
                        i += run;
                    }
                }
            }
            '*' | '_' => {
                let run = count_run(&c, i, ch);
                let prev = if i > 0 { Some(c[i - 1]) } else { None };
                let next = if i + run < n { Some(c[i + run]) } else { None };
                let (pw, nw) = (is_ws(prev), is_ws(next));
                let (pp, np) = (is_punct(prev), is_punct(next));
                let left = !nw && (!np || pw || pp);
                let right = !pw && (!pp || nw || np);
                let (open, close) = if ch == '*' {
                    (left, right)
                } else {
                    (left && (!right || pp), right && (!left || np))
                };
                nodes.push(Node::Delim { ch, count: run, orig: run, open, close });
                i += run;
            }
            '!' if i + 1 < n && c[i + 1] == '[' => {
                nodes.push(Node::Opener { image: true, active: true });
                i += 2;
            }
            '[' => {
                nodes.push(Node::Opener { image: false, active: true });
                i += 1;
            }
            ']' => {
                i = handle_close(&mut nodes, &c, i);
            }
            _ => {
                nodes.push(Node::Text(ch.to_string()));
                i += 1;
            }
        }
    }
    let nodes = finish(nodes);
    render_nodes(&nodes)
}

fn plain(nodes: &[Node]) -> String {
    let mut s = String::new();
    for n in nodes {
        match n {
            Node::Text(t) | Node::Code(t) => s += t,
            Node::Soft | Node::Hard => s.push(' '),
            Node::Em(k) | Node::Strong(k) => s += &plain(k),
            Node::Link { kids, .. } | Node::Image { kids, .. } => s += &plain(kids),
            _ => {}
        }
    }
    s
}

fn render_nodes(nodes: &[Node]) -> String {
    let mut s = String::new();
    for n in nodes {
        match n {
            Node::Text(t) => s += &esc(t),
            Node::Code(t) => s += &format!("<code>{}</code>", esc(t)),
            Node::Soft => s.push('\n'),
            Node::Hard => s += "<br />\n",
            Node::Em(k) => s += &format!("<em>{}</em>", render_nodes(k)),
            Node::Strong(k) => s += &format!("<strong>{}</strong>", render_nodes(k)),
            Node::Link { dest, title, kids } => {
                s += &format!("<a href=\"{}\"", esc(dest));
                if let Some(t) = title {
                    s += &format!(" title=\"{}\"", esc(t));
                }
                s += &format!(">{}</a>", render_nodes(kids));
            }
            Node::Image { dest, title, kids } => {
                s += &format!("<img src=\"{}\" alt=\"{}\"", esc(dest), esc(&plain(kids)));
                if let Some(t) = title {
                    s += &format!(" title=\"{}\"", esc(t));
                }
                s += " />";
            }
            _ => {}
        }
    }
    s
}

fn main() {
    let mut raw = Vec::new();
    io::stdin().read_to_end(&mut raw).unwrap();
    let input = String::from_utf8_lossy(&raw).into_owned();
    let mut lines: Vec<String> = input.split('\n').map(|s| s.to_string()).collect();
    if input.ends_with('\n') {
        lines.pop();
    }
    let blocks = parse_blocks(&lines);
    let out = render_blocks(&blocks);
    io::stdout().write_all(out.as_bytes()).unwrap();
}
