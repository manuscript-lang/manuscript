use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};
use std::io::{Read, Write};

const PRIOS: [&str; 4] = ["low", "medium", "high", "critical"];
const GUARDS: [&str; 5] = ["assignee", "points", "due", "labels", "reporter"];

fn is_ws(c: char) -> bool {
    c == ' ' || c == '\t'
}
fn take_word(s: &str) -> (&str, &str) {
    let s = s.trim_start_matches(is_ws);
    match s.find(is_ws) {
        Some(p) => (&s[..p], s[p..].trim_start_matches(is_ws)),
        None => (s, ""),
    }
}
fn words(s: &str) -> Vec<&str> {
    s.split(is_ws).filter(|w| !w.is_empty()).collect()
}
fn lc(s: &str) -> String {
    s.to_lowercase()
}
fn tokenize(s: &str) -> Result<Vec<String>, String> {
    let mut out = vec![];
    let mut cur = String::new();
    let mut started = false;
    let mut inq = false;
    let cs: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < cs.len() {
        let c = cs[i];
        if inq {
            if c == '\\' && i + 1 < cs.len() && (cs[i + 1] == '"' || cs[i + 1] == '\\') {
                cur.push(cs[i + 1]);
                i += 1;
            } else if c == '"' {
                inq = false;
            } else {
                cur.push(c);
            }
        } else if c == '"' {
            inq = true;
            started = true;
        } else if is_ws(c) {
            if started {
                out.push(std::mem::take(&mut cur));
                started = false;
            }
        } else {
            cur.push(c);
            started = true;
        }
        i += 1;
    }
    if inq {
        return Err("unterminated quote".into());
    }
    if started {
        out.push(cur);
    }
    Ok(out)
}
fn parse_int(s: &str) -> Option<u64> {
    if s.is_empty() || s.len() > 7 || !s.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    if s.len() > 1 && s.starts_with('0') {
        return None;
    }
    let v: u64 = s.parse().ok()?;
    if v > 1000000 {
        None
    } else {
        Some(v)
    }
}
fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return false;
    }
    for (i, c) in b.iter().enumerate() {
        if i != 4 && i != 7 && !c.is_ascii_digit() {
            return false;
        }
    }
    let y: u32 = s[0..4].parse().unwrap();
    let m: u32 = s[5..7].parse().unwrap();
    let d: u32 = s[8..10].parse().unwrap();
    if y < 1 || !(1..=12).contains(&m) || d < 1 {
        return false;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let dim = match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ => {
            if leap {
                29
            } else {
                28
            }
        }
    };
    d <= dim
}
fn valid_state(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b[0].is_ascii_lowercase()
        && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_')
}
fn valid_label(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_' || c == b'-')
}
fn valid_view_name(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b[0].is_ascii_lowercase()
        && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_' || *c == b'-')
}
fn prio_idx(s: &str) -> Option<usize> {
    PRIOS.iter().position(|p| *p == s)
}

struct Issue {
    id: u64,
    title: String,
    state: usize,
    priority: usize,
    assignee: Option<String>,
    reporter: Option<String>,
    points: Option<u64>,
    due: Option<String>,
    labels: Vec<String>,
    comments: Vec<(u64, String, String)>,
    created: u64,
    updated: u64,
    history: Vec<(u64, usize)>,
}

struct Workflow {
    states: Vec<String>,
    initial: usize,
    finals: Vec<bool>,
    trans: Vec<Vec<(usize, Vec<String>)>>,
}

fn intern(names: &mut Vec<String>, s: &str) -> usize {
    if let Some(p) = names.iter().position(|n| n == s) {
        p
    } else {
        names.push(s.to_string());
        names.len() - 1
    }
}

fn parse_workflow(lines: &[String]) -> Result<(Workflow, usize), String> {
    let mut names: Vec<String> = vec![];
    let mut initial: Option<usize> = None;
    let mut finals: Vec<usize> = vec![];
    let mut entries: Vec<(usize, usize, Vec<String>)> = vec![];
    let mut srcs: Vec<usize> = vec![];
    for l in lines {
        let line = l.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let bad = || format!("workflow: bad line '{}'", line);
        if let Some(r) = line.strip_prefix("initial:") {
            let n = r.trim();
            if !valid_state(n) {
                return Err(format!("workflow: bad state name '{}'", n));
            }
            if initial.is_some() {
                return Err("workflow: initial state defined twice".into());
            }
            initial = Some(intern(&mut names, n));
        } else if let Some(r) = line.strip_prefix("final:") {
            for p in r.split(',') {
                let n = p.trim();
                if !valid_state(n) {
                    return Err(format!("workflow: bad state name '{}'", n));
                }
                finals.push(intern(&mut names, n));
            }
        } else if let Some(p) = line.find("->") {
            let src = line[..p].trim();
            if src.is_empty() || src.contains(is_ws) {
                return Err(bad());
            }
            if !valid_state(src) {
                return Err(format!("workflow: bad state name '{}'", src));
            }
            let s = intern(&mut names, src);
            srcs.push(s);
            for e in line[p + 2..].split(',') {
                let w = words(e);
                let (t, guards) = if w.len() == 1 {
                    (w[0], vec![])
                } else if w.len() == 3 && w[1] == "requires" {
                    (w[0], w[2].split('+').collect::<Vec<_>>())
                } else {
                    return Err(bad());
                };
                if !valid_state(t) {
                    return Err(format!("workflow: bad state name '{}'", t));
                }
                for g in &guards {
                    if !GUARDS.contains(g) {
                        return Err(format!("workflow: bad guard field '{}'", g));
                    }
                }
                let ti = intern(&mut names, t);
                entries.push((s, ti, guards.iter().map(|g| g.to_string()).collect()));
            }
        } else {
            return Err(bad());
        }
    }
    let initial = match initial {
        Some(i) => i,
        None => return Err("workflow: initial state missing".into()),
    };
    let mut fin = vec![false; names.len()];
    for f in finals {
        fin[f] = true;
    }
    for s in srcs {
        if fin[s] {
            return Err(format!("workflow: '{}' is final and cannot have transitions", names[s]));
        }
    }
    let mut trans = vec![vec![]; names.len()];
    let n = entries.len();
    for (s, t, g) in entries {
        trans[s].push((t, g));
    }
    Ok((Workflow { states: names, initial, finals: fin, trans }, n))
}

#[derive(Clone)]
struct Term {
    field: String,
    op: String,
    alts: Vec<String>,
}
enum Expr {
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
    Not(Box<Expr>),
    Term(Term),
}
enum Tok {
    LP,
    RP,
    And,
    Or,
    Not,
    Term(String, String, String, bool),
    Word(String),
}
fn tok_text(t: &Tok) -> String {
    match t {
        Tok::LP => "(".into(),
        Tok::RP => ")".into(),
        Tok::And => "AND".into(),
        Tok::Or => "OR".into(),
        Tok::Not => "NOT".into(),
        Tok::Word(w) => w.clone(),
        Tok::Term(f, o, v, _) => format!("{}{}{}", f, o, v),
    }
}
fn lex(s: &str) -> Result<Vec<Tok>, String> {
    let c: Vec<char> = s.chars().collect();
    let n = c.len();
    let mut i = 0;
    let mut out = vec![];
    while i < n {
        if is_ws(c[i]) || c[i] == '\r' || c[i] == '\n' {
            i += 1;
            continue;
        }
        if c[i] == '(' {
            out.push(Tok::LP);
            i += 1;
            continue;
        }
        if c[i] == ')' {
            out.push(Tok::RP);
            i += 1;
            continue;
        }
        let mut j = i;
        while j < n && (c[j].is_ascii_lowercase() || c[j] == '_') {
            j += 1;
        }
        let mut oplen = 0;
        if j > i && j < n {
            let two: String = c[j..(j + 2).min(n)].iter().collect();
            if two == "!=" || two == "<=" || two == ">=" {
                oplen = 2;
            } else if c[j] == ':' || c[j] == '<' || c[j] == '>' || c[j] == '~' {
                oplen = 1;
            }
        }
        if oplen > 0 {
            let field: String = c[i..j].iter().collect();
            let op: String = c[j..j + oplen].iter().collect();
            let mut k = j + oplen;
            let mut val = String::new();
            let mut quoted = false;
            if k < n && c[k] == '"' {
                quoted = true;
                k += 1;
                let mut closed = false;
                while k < n {
                    if c[k] == '\\' && k + 1 < n && (c[k + 1] == '"' || c[k + 1] == '\\') {
                        val.push(c[k + 1]);
                        k += 2;
                    } else if c[k] == '"' {
                        closed = true;
                        k += 1;
                        break;
                    } else {
                        val.push(c[k]);
                        k += 1;
                    }
                }
                if !closed {
                    return Err("query: unterminated quote".into());
                }
            } else {
                while k < n && !is_ws(c[k]) && c[k] != '(' && c[k] != ')' {
                    val.push(c[k]);
                    k += 1;
                }
            }
            out.push(Tok::Term(field, op, val, quoted));
            i = k;
        } else {
            let mut k = i;
            let mut w = String::new();
            while k < n && !is_ws(c[k]) && c[k] != '(' && c[k] != ')' {
                w.push(c[k]);
                k += 1;
            }
            i = k;
            out.push(match w.as_str() {
                "AND" => Tok::And,
                "OR" => Tok::Or,
                "NOT" => Tok::Not,
                _ => Tok::Word(w),
            });
        }
    }
    Ok(out)
}

struct Parser<'a> {
    app: &'a App,
    toks: Vec<Tok>,
    pos: usize,
}
const END: &str = "query: unexpected end of query";
impl<'a> Parser<'a> {
    fn or(&mut self) -> Result<Expr, String> {
        let mut l = self.and()?;
        while matches!(self.toks.get(self.pos), Some(Tok::Or)) {
            self.pos += 1;
            let r = self.and()?;
            l = Expr::Or(Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn and(&mut self) -> Result<Expr, String> {
        let mut l = self.not()?;
        loop {
            match self.toks.get(self.pos) {
                Some(Tok::And) => {
                    self.pos += 1;
                }
                Some(Tok::Term(..)) | Some(Tok::Not) | Some(Tok::LP) | Some(Tok::Word(_)) => {}
                _ => break,
            }
            let r = self.not()?;
            l = Expr::And(Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn not(&mut self) -> Result<Expr, String> {
        let t = match self.toks.get(self.pos) {
            None => return Err(END.into()),
            Some(t) => t,
        };
        match t {
            Tok::Not => {
                self.pos += 1;
                Ok(Expr::Not(Box::new(self.not()?)))
            }
            Tok::LP => {
                self.pos += 1;
                let e = self.or()?;
                match self.toks.get(self.pos) {
                    None => Err(END.into()),
                    Some(Tok::RP) => {
                        self.pos += 1;
                        Ok(e)
                    }
                    Some(o) => Err(format!("query: unexpected token '{}'", tok_text(o))),
                }
            }
            Tok::Term(f, o, v, q) => {
                let r = self.app.validate(f, o, v, *q)?;
                self.pos += 1;
                Ok(Expr::Term(r))
            }
            o => Err(format!("query: unexpected token '{}'", tok_text(o))),
        }
    }
}

fn collect_refs(e: &Expr, out: &mut Vec<String>) {
    match e {
        Expr::And(a, b) | Expr::Or(a, b) => {
            collect_refs(a, out);
            collect_refs(b, out);
        }
        Expr::Not(a) => collect_refs(a, out),
        Expr::Term(t) => {
            if t.field == "view" {
                out.push(t.alts[0].clone());
            }
        }
    }
}

// returns (filter text, sort text, limit)
fn split_query(text: &str) -> Result<(String, Option<String>, Option<usize>), String> {
    let tr = text.trim_end();
    let mut filter = tr.to_string();
    let mut limit = None;
    let (head, last) = match tr.rfind(is_ws) {
        Some(p) => (&tr[..p], &tr[p + 1..]),
        None => ("", tr),
    };
    if !last.is_empty() && !head.is_empty() {
        let h2 = head.trim_end();
        if h2.ends_with("limit") {
            let pre = &h2[..h2.len() - 5];
            if pre.is_empty() || pre.ends_with(is_ws) {
                match parse_int(last) {
                    Some(n) => limit = Some(n as usize),
                    None => return Err(format!("bad limit '{}'", last)),
                }
                filter = pre.to_string();
            }
        }
    }
    let b = filter.as_bytes();
    let mut sort = None;
    let mut i = 0;
    while i + 4 < b.len() + 0 {
        if &b[i..i + 4] == b"sort" && (i == 0 || b[i - 1] == b' ' || b[i - 1] == b'\t') && (b[i + 4] == b' ' || b[i + 4] == b'\t') {
            sort = Some(filter[i + 4..].to_string());
            filter = filter[..i].to_string();
            break;
        }
        i += 1;
    }
    Ok((filter, sort, limit))
}

const SORT_FIELDS: [&str; 10] = ["id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due"];
fn parse_sort(s: &str) -> Result<Vec<(String, bool)>, String> {
    let mut out = vec![];
    for p in s.split(|c: char| c == ',' || is_ws(c)) {
        if p.is_empty() {
            continue;
        }
        let (d, n) = match p.strip_prefix('-') {
            Some(r) => (true, r),
            None => (false, p),
        };
        if !SORT_FIELDS.contains(&n) {
            return Err(format!("bad sort field '{}'", n));
        }
        out.push((n.to_string(), d));
    }
    Ok(out)
}
fn opt_cmp<T: Ord>(a: &Option<T>, b: &Option<T>) -> Ordering {
    match (a, b) {
        (Some(x), Some(y)) => x.cmp(y),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        (None, None) => Ordering::Equal,
    }
}

#[derive(Default)]
struct Changes {
    title: Option<String>,
    priority: Option<usize>,
    assignee: Option<Option<String>>,
    points: Option<Option<u64>>,
    due: Option<Option<String>>,
    labels: Option<Vec<String>>,
    reporter: Option<Option<String>>,
}
fn parse_fields(tokens: &[String]) -> Result<Changes, String> {
    let mut ch = Changes::default();
    for t in tokens {
        let p = match t.find('=') {
            Some(p) if p > 0 => p,
            _ => return Err(format!("expected field=value, got '{}'", t)),
        };
        let f = &t[..p];
        let v = &t[p + 1..];
        match f {
            "state" => return Err("use move to change state".into()),
            "title" => {
                if v.trim().is_empty() {
                    return Err("empty title".into());
                }
                ch.title = Some(v.to_string());
            }
            "priority" => match prio_idx(v) {
                Some(i) => ch.priority = Some(i),
                None => return Err(format!("bad priority '{}'", v)),
            },
            "points" => {
                if v == "none" {
                    ch.points = Some(None);
                } else {
                    match parse_int(v) {
                        Some(n) => ch.points = Some(Some(n)),
                        None => return Err(format!("bad points '{}'", v)),
                    }
                }
            }
            "due" => {
                if v == "none" {
                    ch.due = Some(None);
                } else if valid_date(v) {
                    ch.due = Some(Some(v.to_string()));
                } else {
                    return Err(format!("bad date '{}'", v));
                }
            }
            "labels" => {
                if v == "none" {
                    ch.labels = Some(vec![]);
                } else {
                    let mut set = BTreeSet::new();
                    for l in v.split(',') {
                        let l = lc(l);
                        if !valid_label(&l) {
                            return Err(format!("bad label '{}'", l));
                        }
                        set.insert(l);
                    }
                    ch.labels = Some(set.into_iter().collect());
                }
            }
            "assignee" => {
                if v == "none" {
                    ch.assignee = Some(None);
                } else if v.trim().is_empty() {
                    return Err("empty assignee".into());
                } else {
                    ch.assignee = Some(Some(v.to_string()));
                }
            }
            "reporter" => {
                if v == "none" {
                    ch.reporter = Some(None);
                } else if v.trim().is_empty() {
                    return Err("empty reporter".into());
                } else {
                    ch.reporter = Some(Some(v.to_string()));
                }
            }
            _ => return Err(format!("unknown field '{}'", f)),
        }
    }
    Ok(ch)
}
fn dash(o: &Option<String>) -> String {
    o.clone().unwrap_or_else(|| "-".into())
}
fn dashl(l: &[String]) -> String {
    if l.is_empty() {
        "-".into()
    } else {
        l.join(",")
    }
}

struct App {
    wf: Option<Workflow>,
    issues: BTreeMap<u64, Issue>,
    next_id: u64,
    t: u64,
    actor: String,
    today: String,
    log: Vec<(u64, String, u64, String)>,
    views: BTreeMap<String, String>,
    out: String,
}

impl App {
    fn say(&mut self, s: &str) {
        self.out.push_str(s);
        self.out.push('\n');
    }
    fn addlog(&mut self, id: u64, d: String) {
        self.log.push((self.t, self.actor.clone(), id, d));
    }
    fn validate(&self, field: &str, op: &str, val: &str, quoted: bool) -> Result<Term, String> {
        let split = !quoted && field != "view" && (op == ":" || op == "!=" || op == "~") && val.contains('|');
        let alts: Vec<String> = if split { val.split('|').map(|s| s.to_string()).collect() } else { vec![val.to_string()] };
        let badop = || Err(format!("query: bad operator '{}' for field '{}'", op, field));
        let badv = |v: &str| Err(format!("query: bad value '{}' for field '{}'", v, field));
        let ord = matches!(op, "<" | "<=" | ">" | ">=");
        let full = matches!(op, ":" | "!=" | "<" | "<=" | ">" | ">=");
        match field {
            "id" | "created" | "updated" => {
                if !full {
                    return badop();
                }
                for a in &alts {
                    if parse_int(a).is_none() {
                        return badv(a);
                    }
                }
            }
            "points" => {
                if !full {
                    return badop();
                }
                for a in &alts {
                    if parse_int(a).is_none() && !(a == "none" && !ord) {
                        return badv(a);
                    }
                }
            }
            "title" | "assignee" | "reporter" | "label" | "labels" => {
                if !(op == ":" || op == "!=" || op == "~") {
                    return badop();
                }
            }
            "text" => {
                if op != "~" {
                    return badop();
                }
            }
            "state" => {
                if !(op == ":" || op == "!=") {
                    return badop();
                }
                let wf = self.wf.as_ref();
                for a in &alts {
                    if !wf.map_or(false, |w| w.states.contains(a)) {
                        return badv(a);
                    }
                }
            }
            "priority" => {
                if !full {
                    return badop();
                }
                for a in &alts {
                    if prio_idx(a).is_none() {
                        return badv(a);
                    }
                }
            }
            "due" => {
                if !full {
                    return badop();
                }
                for a in &alts {
                    if !(valid_date(a) || (a == "none" && !ord)) {
                        return badv(a);
                    }
                }
            }
            "is" | "has" => {
                if op != ":" {
                    return badop();
                }
                let okv: &[&str] = if field == "is" {
                    &["open", "final", "overdue", "unassigned"]
                } else {
                    &["assignee", "due", "points", "labels", "comments", "reporter"]
                };
                for a in &alts {
                    if !okv.contains(&a.as_str()) {
                        return badv(a);
                    }
                }
            }
            "view" => {
                if op != ":" {
                    return badop();
                }
                if !self.views.contains_key(val) {
                    return Err(format!("query: unknown view '{}'", val));
                }
            }
            _ => return Err(format!("query: unknown field '{}'", field)),
        }
        Ok(Term { field: field.to_string(), op: op.to_string(), alts })
    }
    fn parse_filter(&self, s: &str) -> Result<Option<Expr>, String> {
        let toks = lex(s)?;
        if toks.is_empty() {
            return Ok(None);
        }
        let mut p = Parser { app: self, toks, pos: 0 };
        let e = p.or()?;
        if p.pos < p.toks.len() {
            return Err(format!("query: unexpected token '{}'", tok_text(&p.toks[p.pos])));
        }
        Ok(Some(e))
    }
    fn eval(&self, e: &Expr, is: &Issue) -> bool {
        match e {
            Expr::And(a, b) => self.eval(a, is) && self.eval(b, is),
            Expr::Or(a, b) => self.eval(a, is) || self.eval(b, is),
            Expr::Not(a) => !self.eval(a, is),
            Expr::Term(t) => self.eval_term(t, is),
        }
    }
    fn is_final(&self, is: &Issue) -> bool {
        self.wf.as_ref().map_or(false, |w| w.finals[is.state])
    }
    fn eval_term(&self, t: &Term, is: &Issue) -> bool {
        let op = t.op.as_str();
        let f = t.field.as_str();
        if f == "view" {
            let q = match self.views.get(&t.alts[0]) {
                Some(q) => q.clone(),
                None => return false,
            };
            let (flt, _, _) = match split_query(&q) {
                Ok(x) => x,
                Err(_) => return false,
            };
            return match self.parse_filter(&flt) {
                Ok(Some(e)) => self.eval(&e, is),
                Ok(None) => true,
                Err(_) => false,
            };
        }
        if matches!(op, "<" | "<=" | ">" | ">=") {
            let alt = &t.alts[0];
            let num = parse_int(alt).unwrap_or(0);
            let o = match f {
                "id" => Some(is.id.cmp(&num)),
                "created" => Some(is.created.cmp(&num)),
                "updated" => Some(is.updated.cmp(&num)),
                "points" => is.points.map(|p| p.cmp(&num)),
                "priority" => Some(is.priority.cmp(&prio_idx(alt).unwrap_or(0))),
                "due" => is.due.as_ref().map(|d| d.as_str().cmp(alt.as_str())),
                _ => None,
            };
            return match o {
                None => false,
                Some(o) => match op {
                    "<" => o == Ordering::Less,
                    "<=" => o != Ordering::Greater,
                    ">" => o == Ordering::Greater,
                    _ => o != Ordering::Less,
                },
            };
        }
        let tilde = op == "~";
        let any = t.alts.iter().any(|a| self.match_one(f, tilde, a, is));
        if op == "!=" {
            !any
        } else {
            any
        }
    }
    fn match_one(&self, f: &str, tilde: bool, a: &str, is: &Issue) -> bool {
        let sm = |v: Option<&String>| -> bool {
            match v {
                Some(v) => {
                    if tilde {
                        lc(v).contains(&lc(a))
                    } else {
                        lc(v) == lc(a)
                    }
                }
                None => !tilde && a == "none",
            }
        };
        match f {
            "id" => parse_int(a) == Some(is.id),
            "created" => parse_int(a) == Some(is.created),
            "updated" => parse_int(a) == Some(is.updated),
            "points" => {
                if a == "none" {
                    is.points.is_none()
                } else {
                    is.points.is_some() && is.points == parse_int(a)
                }
            }
            "title" => sm(Some(&is.title)),
            "assignee" => sm(is.assignee.as_ref()),
            "reporter" => sm(is.reporter.as_ref()),
            "text" => {
                let a = lc(a);
                lc(&is.title).contains(&a) || is.comments.iter().any(|c| lc(&c.2).contains(&a))
            }
            "state" => self.wf.as_ref().map_or(false, |w| w.states[is.state] == a),
            "priority" => PRIOS[is.priority] == a,
            "due" => match &is.due {
                Some(d) => d == a,
                None => a == "none",
            },
            "label" | "labels" => {
                let a = lc(a);
                if tilde {
                    is.labels.iter().any(|l| l.contains(&a))
                } else if a == "none" {
                    is.labels.is_empty()
                } else {
                    is.labels.contains(&a)
                }
            }
            "is" => match a {
                "open" => !self.is_final(is),
                "final" => self.is_final(is),
                "overdue" => !self.is_final(is) && is.due.as_ref().map_or(false, |d| d.as_str() < self.today.as_str()),
                "unassigned" => is.assignee.is_none(),
                _ => false,
            },
            "has" => match a {
                "assignee" => is.assignee.is_some(),
                "due" => is.due.is_some(),
                "points" => is.points.is_some(),
                "labels" => !is.labels.is_empty(),
                "comments" => !is.comments.is_empty(),
                "reporter" => is.reporter.is_some(),
                _ => false,
            },
            _ => false,
        }
    }
    fn matching(&self, e: &Option<Expr>) -> Vec<&Issue> {
        self.issues.values().filter(|i| e.as_ref().map_or(true, |e| self.eval(e, i))).collect()
    }
    fn cmp_field(&self, f: &str, a: &Issue, b: &Issue) -> Ordering {
        match f {
            "id" => a.id.cmp(&b.id),
            "created" => a.created.cmp(&b.created),
            "updated" => a.updated.cmp(&b.updated),
            "priority" => a.priority.cmp(&b.priority),
            "points" => opt_cmp(&a.points, &b.points),
            "state" => a.state.cmp(&b.state),
            "title" => lc(&a.title).cmp(&lc(&b.title)),
            "assignee" => opt_cmp(&a.assignee.as_ref().map(|s| lc(s)), &b.assignee.as_ref().map(|s| lc(s))),
            "reporter" => opt_cmp(&a.reporter.as_ref().map(|s| lc(s)), &b.reporter.as_ref().map(|s| lc(s))),
            "due" => opt_cmp(&a.due, &b.due),
            _ => Ordering::Equal,
        }
    }
    fn issue_line(&self, i: &Issue) -> String {
        let st = self.wf.as_ref().map(|w| w.states[i.state].clone()).unwrap_or_default();
        format!(
            "#{} | {} | {} | {} | {} | {} | {} | {}",
            i.id,
            st,
            PRIOS[i.priority],
            dash(&i.assignee),
            i.points.map_or("-".to_string(), |p| p.to_string()),
            dash(&i.due),
            dashl(&i.labels),
            i.title
        )
    }
    fn run_query(&self, filter: &str, sort: &[(String, bool)], limit: Option<usize>) -> Result<Vec<String>, String> {
        let e = self.parse_filter(filter)?;
        let mut v = self.matching(&e);
        v.sort_by(|a, b| {
            for (f, d) in sort {
                let mut o = self.cmp_field(f, a, b);
                if *d {
                    o = o.reverse();
                }
                if o != Ordering::Equal {
                    return o;
                }
            }
            a.id.cmp(&b.id)
        });
        if let Some(l) = limit {
            v.truncate(l);
        }
        let mut out: Vec<String> = v.iter().map(|i| self.issue_line(i)).collect();
        out.push(if v.len() == 1 { "(1 issue)".into() } else { format!("({} issues)", v.len()) });
        Ok(out)
    }
    fn print_lines(&mut self, r: Result<Vec<String>, String>) {
        match r {
            Ok(v) => {
                for l in v {
                    self.say(&l);
                }
            }
            Err(e) => self.say(&format!("error: {}", e)),
        }
    }
    fn do_list(&mut self, text: &str) -> Result<Vec<String>, String> {
        let (f, s, l) = split_query(text)?;
        let e = self.parse_filter(&f)?;
        drop(e);
        let sort = parse_sort(s.as_deref().unwrap_or(""))?;
        self.run_query(&f, &sort, l)
    }
    fn get_id(&self, arg: &str, any_issued: bool) -> Result<u64, String> {
        let d = arg.strip_prefix('#').unwrap_or(arg);
        if d.is_empty() || !d.bytes().all(|c| c.is_ascii_digit()) {
            return Err(format!("bad issue id '{}'", arg));
        }
        let n = d.trim_start_matches('0');
        if n.is_empty() {
            return Err(format!("bad issue id '{}'", arg));
        }
        let v: u64 = if n.len() > 18 { u64::MAX } else { n.parse().unwrap() };
        let ok = if any_issued { v < self.next_id } else { self.issues.contains_key(&v) };
        if ok {
            Ok(v)
        } else {
            Err(format!("no such issue #{}", n))
        }
    }
    fn live_id(&self, arg: &str) -> Result<u64, String> {
        self.get_id(arg, false)
    }
    fn final_check(&self, id: u64) -> Result<(), String> {
        let i = &self.issues[&id];
        if self.is_final(i) {
            return Err(format!("#{} is in final state '{}'", id, self.wf.as_ref().unwrap().states[i.state]));
        }
        Ok(())
    }
    fn apply_changes(&mut self, id: u64, ch: Changes) -> Result<String, String> {
        let mut d: Vec<String> = vec![];
        {
            let i = &self.issues[&id];
            if let Some(t) = &ch.title {
                if *t != i.title {
                    d.push(format!("title: {} -> {}", i.title, t));
                }
            }
            if let Some(p) = ch.priority {
                if p != i.priority {
                    d.push(format!("priority: {} -> {}", PRIOS[i.priority], PRIOS[p]));
                }
            }
            if let Some(a) = &ch.assignee {
                if *a != i.assignee {
                    d.push(format!("assignee: {} -> {}", dash(&i.assignee), dash(a)));
                }
            }
            if let Some(p) = &ch.points {
                if *p != i.points {
                    let f = |x: &Option<u64>| x.map_or("-".to_string(), |v| v.to_string());
                    d.push(format!("points: {} -> {}", f(&i.points), f(p)));
                }
            }
            if let Some(a) = &ch.due {
                if *a != i.due {
                    d.push(format!("due: {} -> {}", dash(&i.due), dash(a)));
                }
            }
            if let Some(l) = &ch.labels {
                if *l != i.labels {
                    d.push(format!("labels: {} -> {}", dashl(&i.labels), dashl(l)));
                }
            }
            if let Some(a) = &ch.reporter {
                if *a != i.reporter {
                    d.push(format!("reporter: {} -> {}", dash(&i.reporter), dash(a)));
                }
            }
        }
        if d.is_empty() {
            return Ok(format!("#{} unchanged", id));
        }
        self.t += 1;
        let t = self.t;
        let i = self.issues.get_mut(&id).unwrap();
        i.updated = t;
        if let Some(x) = ch.title {
            i.title = x;
        }
        if let Some(x) = ch.priority {
            i.priority = x;
        }
        if let Some(x) = ch.assignee {
            i.assignee = x;
        }
        if let Some(x) = ch.points {
            i.points = x;
        }
        if let Some(x) = ch.due {
            i.due = x;
        }
        if let Some(x) = ch.labels {
            i.labels = x;
        }
        if let Some(x) = ch.reporter {
            i.reporter = x;
        }
        for x in d {
            self.addlog(id, x);
        }
        Ok(format!("updated #{}", id))
    }
    fn do_edit(&mut self, idarg: &str, fields: &[String]) -> Result<String, String> {
        let id = self.live_id(idarg)?;
        self.final_check(id)?;
        let ch = parse_fields(fields)?;
        if fields.is_empty() {
            return Err("usage: edit ID field=value...".into());
        }
        self.apply_changes(id, ch)
    }
    fn do_label(&mut self, idarg: &str, toks: &[String]) -> Result<String, String> {
        let id = self.live_id(idarg)?;
        self.final_check(id)?;
        let mut set: BTreeSet<String> = self.issues[&id].labels.iter().cloned().collect();
        for t in toks {
            let (rem, name) = if let Some(r) = t.strip_prefix('-') {
                (true, r)
            } else if let Some(r) = t.strip_prefix('+') {
                (false, r)
            } else {
                (false, t.as_str())
            };
            let l = lc(name);
            if !valid_label(&l) {
                return Err(format!("bad label '{}'", l));
            }
            if rem {
                set.remove(&l);
            } else {
                set.insert(l);
            }
        }
        let ch = Changes { labels: Some(set.into_iter().collect()), ..Default::default() };
        self.apply_changes(id, ch)
    }
    fn do_move(&mut self, idarg: &str, state: &str, comment: &str) -> Result<String, String> {
        let id = self.live_id(idarg)?;
        self.final_check(id)?;
        let wf = self.wf.as_ref().unwrap();
        let ti = match wf.states.iter().position(|s| s == state) {
            Some(x) => x,
            None => return Err(format!("unknown state '{}'", state)),
        };
        let i = &self.issues[&id];
        let from = i.state;
        if from == ti {
            return Err(format!("already in state '{}'", state));
        }
        let ent = match wf.trans[from].iter().find(|e| e.0 == ti) {
            Some(e) => e,
            None => return Err(format!("transition '{} -> {}' not allowed", wf.states[from], state)),
        };
        let missing: Vec<&str> = ent
            .1
            .iter()
            .filter(|g| match g.as_str() {
                "assignee" => i.assignee.is_none(),
                "points" => i.points.is_none(),
                "due" => i.due.is_none(),
                "labels" => i.labels.is_empty(),
                "reporter" => i.reporter.is_none(),
                _ => false,
            })
            .map(|g| g.as_str())
            .collect();
        if !missing.is_empty() {
            return Err(format!("cannot move #{} to {}: missing {}", id, state, missing.join(", ")));
        }
        let fname = wf.states[from].clone();
        self.t += 1;
        let t = self.t;
        let actor = self.actor.clone();
        let i = self.issues.get_mut(&id).unwrap();
        i.state = ti;
        i.updated = t;
        i.history.push((t, ti));
        if !comment.is_empty() {
            i.comments.push((t, actor, comment.to_string()));
        }
        self.addlog(id, format!("state: {} -> {}", fname, state));
        if !comment.is_empty() {
            self.addlog(id, format!("comment: {}", comment));
        }
        Ok(format!("moved #{}: {} -> {}", id, fname, state))
    }
    fn cmd_create(&mut self, rest: &str) -> Result<String, String> {
        if self.wf.is_none() {
            return Err("no workflow defined".into());
        }
        let toks = tokenize(rest)?;
        if toks.is_empty() {
            return Err("usage: create TITLE [field=value...]".into());
        }
        let first = toks[0].clone();
        if first.trim().is_empty() {
            return Err("empty title".into());
        }
        let ch = parse_fields(&toks[1..])?;
        self.t += 1;
        let t = self.t;
        let id = self.next_id;
        self.next_id += 1;
        let init = self.wf.as_ref().unwrap().initial;
        let title = ch.title.clone().unwrap_or(first.clone());
        let is = Issue {
            id,
            title: title.clone(),
            state: init,
            priority: ch.priority.unwrap_or(1),
            assignee: ch.assignee.clone().flatten(),
            reporter: match &ch.reporter {
                Some(r) => r.clone(),
                None => Some(self.actor.clone()),
            },
            points: ch.points.flatten(),
            due: ch.due.clone().flatten(),
            labels: ch.labels.clone().unwrap_or_default(),
            comments: vec![],
            created: t,
            updated: t,
            history: vec![(t, init)],
        };
        self.addlog(id, format!("created \"{}\"", first));
        if title != first {
            self.addlog(id, format!("title: {} -> {}", first, title));
        }
        if is.priority != 1 {
            self.addlog(id, format!("priority: medium -> {}", PRIOS[is.priority]));
        }
        if let Some(a) = &is.assignee {
            self.addlog(id, format!("assignee: - -> {}", a));
        }
        if let Some(p) = is.points {
            self.addlog(id, format!("points: - -> {}", p));
        }
        if let Some(a) = &is.due {
            self.addlog(id, format!("due: - -> {}", a));
        }
        if !is.labels.is_empty() {
            self.addlog(id, format!("labels: - -> {}", is.labels.join(",")));
        }
        if let Some(Some(r)) = &ch.reporter {
            self.addlog(id, format!("reporter: - -> {}", r));
        }
        self.issues.insert(id, is);
        Ok(format!("created #{}", id))
    }
    fn cmd_show(&mut self, rest: &str) -> Result<String, String> {
        let w = words(rest);
        if w.len() != 1 {
            return Err("usage: show ID".into());
        }
        let id = self.live_id(w[0])?;
        let i = &self.issues[&id];
        let mut s = String::new();
        s += &format!("#{} {}\n", i.id, i.title);
        s += &format!("  state: {}\n", self.wf.as_ref().unwrap().states[i.state]);
        s += &format!("  priority: {}\n", PRIOS[i.priority]);
        s += &format!("  assignee: {}\n", dash(&i.assignee));
        s += &format!("  points: {}\n", i.points.map_or("-".to_string(), |p| p.to_string()));
        s += &format!("  due: {}\n", dash(&i.due));
        s += &format!("  labels: {}\n", if i.labels.is_empty() { "-".to_string() } else { i.labels.join(", ") });
        s += &format!("  reporter: {}\n", dash(&i.reporter));
        s += &format!("  created: t={}, updated: t={}\n", i.created, i.updated);
        s += &format!("  comments: {}", i.comments.len());
        for c in &i.comments {
            s += &format!("\n    [t={} {}] {}", c.0, c.1, c.2);
        }
        Ok(s)
    }
    fn cmd_log(&mut self, rest: &str) -> Result<Vec<String>, String> {
        let w = words(rest);
        let usage = || Err("usage: log [ID] [tail N]".to_string());
        let (mut idf, mut tail): (Option<u64>, Option<usize>) = (None, None);
        let mut k = 0;
        if !w.is_empty() && w[0] != "tail" {
            idf = Some(self.get_id(w[0], true)?);
            k = 1;
        }
        if k < w.len() {
            if w[k] != "tail" || w.len() != k + 2 {
                return usage();
            }
            tail = match parse_int(w[k + 1]) {
                Some(n) => Some(n as usize),
                None => return Err(format!("bad tail '{}'", w[k + 1])),
            };
        }
        let mut v: Vec<String> = self
            .log
            .iter()
            .filter(|e| idf.map_or(true, |i| e.2 == i))
            .map(|e| format!("t={} {} #{} {}", e.0, e.1, e.2, e.3))
            .collect();
        if let Some(n) = tail {
            let l = v.len();
            v = v.split_off(l - n.min(l));
        }
        if v.is_empty() {
            v.push("(no log entries)".into());
        }
        Ok(v)
    }
    fn view_refs(&self, name: &str) -> Vec<String> {
        let mut out = vec![];
        if let Some(q) = self.views.get(name) {
            if let Ok((f, _, _)) = split_query(q) {
                if let Ok(Some(e)) = self.parse_filter(&f) {
                    collect_refs(&e, &mut out);
                }
            }
        }
        out
    }
    fn view_uses(&self, from: &str) -> BTreeSet<String> {
        let mut seen = BTreeSet::new();
        let mut st = self.view_refs(from);
        while let Some(v) = st.pop() {
            if seen.insert(v.clone()) {
                st.extend(self.view_refs(&v));
            }
        }
        seen
    }
    fn cmd_view(&mut self, rest: &str) {
        let (sub, r) = take_word(rest);
        let gen = "usage: view save|run|list|show|delete";
        let res: Result<Vec<String>, String> = (|| match sub {
            "save" => {
                let (name, q) = take_word(r);
                if name.is_empty() {
                    return Err("usage: view save NAME QUERY".into());
                }
                if !valid_view_name(name) {
                    return Err(format!("bad view name '{}'", name));
                }
                let q = q.trim();
                let (f, s, _l) = split_query(q)?;
                let e = self.parse_filter(&f)?;
                parse_sort(s.as_deref().unwrap_or(""))?;
                let mut refs = vec![];
                if let Some(e) = &e {
                    collect_refs(e, &mut refs);
                }
                let mut seen = BTreeSet::new();
                while let Some(v) = refs.pop() {
                    if v == name {
                        return Err(format!("view '{}' would reference itself", name));
                    }
                    if seen.insert(v.clone()) {
                        refs.extend(self.view_refs(&v));
                    }
                }
                self.views.insert(name.to_string(), q.to_string());
                Ok(vec![format!("saved view {}", name)])
            }
            "run" => {
                let (name, extra) = take_word(r);
                if name.is_empty() {
                    return Err("usage: view run NAME [sort FIELDS] [limit N]".into());
                }
                let q = match self.views.get(name) {
                    Some(q) => q.clone(),
                    None => return Err(format!("unknown view '{}'", name)),
                };
                let (f, s, l) = split_query(&q)?;
                let (f2, s2, l2) = split_query(extra)?;
                if !f2.trim().is_empty() {
                    return Err(format!("unexpected '{}'", f2.trim()));
                }
                let s = s2.or(s);
                let l = l2.or(l);
                let sort = parse_sort(s.as_deref().unwrap_or(""))?;
                self.run_query(&f, &sort, l)
            }
            "list" => {
                if self.views.is_empty() {
                    return Ok(vec!["(no views)".into()]);
                }
                Ok(self.views.iter().map(|(k, v)| format!("{}: {}", k, v)).collect())
            }
            "show" => {
                let w = words(r);
                if w.len() != 1 {
                    return Err("usage: view show NAME".into());
                }
                match self.views.get(w[0]) {
                    Some(q) => Ok(vec![format!("{}: {}", w[0], q)]),
                    None => Err(format!("unknown view '{}'", w[0])),
                }
            }
            "delete" => {
                let w = words(r);
                if w.len() != 1 {
                    return Err("usage: view delete NAME".into());
                }
                if !self.views.contains_key(w[0]) {
                    return Err(format!("unknown view '{}'", w[0]));
                }
                for m in self.views.keys() {
                    if m != w[0] && self.view_uses(m).contains(w[0]) {
                        return Err(format!("view '{}' is used by '{}'", w[0], m));
                    }
                }
                self.views.remove(w[0]);
                Ok(vec![format!("deleted view {}", w[0])])
            }
            _ => Err(gen.into()),
        })();
        self.print_lines(res);
    }
    fn cmd_bulk(&mut self, rest: &str) -> Result<Vec<String>, String> {
        let usage = || Err("usage: bulk ACTION... where QUERY".to_string());
        let b = rest.as_bytes();
        let mut pos = None;
        let mut i = 0;
        while i + 5 <= b.len() {
            if &b[i..i + 5] == b"where" && (i == 0 || b[i - 1] == b' ' || b[i - 1] == b'\t') && (i + 5 == b.len() || b[i + 5] == b' ' || b[i + 5] == b'\t') {
                pos = Some(i);
                break;
            }
            i += 1;
        }
        let p = match pos {
            Some(p) => p,
            None => return usage(),
        };
        let action = &rest[..p];
        let query = &rest[p + 5..];
        if action.trim().is_empty() {
            return usage();
        }
        let toks = tokenize(action)?;
        if toks.is_empty() {
            return usage();
        }
        let name = toks[0].as_str();
        match name {
            "move" => {
                if toks.len() != 2 {
                    return Err("usage: bulk move STATE where QUERY".into());
                }
            }
            "assign" => {
                if toks.len() != 2 {
                    return Err("usage: bulk assign NAME where QUERY".into());
                }
            }
            "label" => {
                if toks.len() < 2 {
                    return Err("usage: bulk label +label... where QUERY".into());
                }
            }
            "set" => {
                if toks.len() < 2 {
                    return Err("usage: bulk set field=value... where QUERY".into());
                }
            }
            _ => return Err(format!("unknown bulk action '{}'", name)),
        }
        let e = self.parse_filter(query.trim())?;
        let ids: Vec<u64> = self.matching(&e).iter().map(|i| i.id).collect();
        let (mut ok, mut failed) = (0, 0);
        let mut out = vec![];
        for id in ids {
            let ids = id.to_string();
            let r = match name {
                "move" => self.do_move(&ids, &toks[1], ""),
                "assign" => self.do_edit(&ids, &[format!("assignee={}", toks[1])]),
                "label" => self.do_label(&ids, &toks[1..]),
                _ => self.do_edit(&ids, &toks[1..]),
            };
            match r {
                Ok(s) => {
                    ok += 1;
                    out.push(s);
                }
                Err(m) => {
                    failed += 1;
                    out.push(format!("#{} error: {}", id, m));
                }
            }
        }
        out.push(format!("bulk: {} ok, {} failed", ok, failed));
        Ok(out)
    }
    fn cmd_report(&mut self, rest: &str) -> Result<Vec<String>, String> {
        let (sub, r) = take_word(rest);
        let mut out = vec![];
        match sub {
            "summary" => {
                let wf = match &self.wf {
                    Some(w) => w,
                    None => {
                        let w = Workflow { states: vec![], initial: 0, finals: vec![], trans: vec![] };
                        self.wf = Some(w);
                        self.wf.as_ref().unwrap()
                    }
                };
                let total = self.issues.len();
                let open = self.issues.values().filter(|i| !wf.finals[i.state]).count();
                out.push(format!("issues: {} (open {}, final {})", total, open, total - open));
                out.push("by state:".into());
                for (k, s) in wf.states.iter().enumerate() {
                    out.push(format!("  {}: {}", s, self.issues.values().filter(|i| i.state == k).count()));
                }
                out.push("by priority:".into());
                for p in (0..4).rev() {
                    out.push(format!("  {}: {}", PRIOS[p], self.issues.values().filter(|i| i.priority == p).count()));
                }
                let oi: Vec<&Issue> = self.issues.values().filter(|i| !wf.finals[i.state]).collect();
                out.push(format!("unassigned: {}", oi.iter().filter(|i| i.assignee.is_none()).count()));
                out.push(format!("overdue: {}", oi.iter().filter(|i| i.due.as_ref().map_or(false, |d| d.as_str() < self.today.as_str())).count()));
                out.push(format!("open points: {}", oi.iter().map(|i| i.points.unwrap_or(0)).sum::<u64>()));
            }
            "workload" => {
                let oi: Vec<&Issue> = self.issues.values().filter(|i| !self.is_final(i)).collect();
                if oi.is_empty() {
                    out.push("(no open issues)".into());
                } else {
                    // key -> (display, count, points)
                    let mut g: Vec<(String, String, u64, u64)> = vec![];
                    let (mut uc, mut up) = (0u64, 0u64);
                    for i in &oi {
                        match &i.assignee {
                            Some(a) => {
                                let k = lc(a);
                                let p = i.points.unwrap_or(0);
                                if let Some(e) = g.iter_mut().find(|e| e.0 == k) {
                                    e.2 += 1;
                                    e.3 += p;
                                } else {
                                    g.push((k, a.clone(), 1, p));
                                }
                            }
                            None => {
                                uc += 1;
                                up += i.points.unwrap_or(0);
                            }
                        }
                    }
                    g.sort_by(|a, b| b.3.cmp(&a.3).then(b.2.cmp(&a.2)).then(a.0.cmp(&b.0)));
                    let f = |n: &str, c: u64, p: u64| format!("{}: {} {}, {} points", n, c, if c == 1 { "issue" } else { "issues" }, p);
                    for e in &g {
                        out.push(f(&e.1, e.2, e.3));
                    }
                    if uc > 0 {
                        out.push(f("unassigned", uc, up));
                    }
                }
            }
            "labels" => {
                let e = self.parse_filter(r.trim())?;
                let mut m: BTreeMap<String, u64> = BTreeMap::new();
                for i in self.matching(&e) {
                    for l in &i.labels {
                        *m.entry(l.clone()).or_insert(0) += 1;
                    }
                }
                let mut v: Vec<(String, u64)> = m.into_iter().collect();
                v.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
                if v.is_empty() {
                    out.push("(no labels)".into());
                }
                for (l, c) in v {
                    out.push(format!("{}: {}", l, c));
                }
            }
            "timeline" => {
                let w = words(r);
                if w.len() != 1 {
                    return Err("usage: report timeline ID".into());
                }
                let id = self.live_id(w[0])?;
                let i = &self.issues[&id];
                let wf = self.wf.as_ref().unwrap();
                for (k, (t, s)) in i.history.iter().enumerate() {
                    let end = i.history.get(k + 1).map_or(self.t, |x| x.0);
                    out.push(format!("{}: t={}..{} ({})", wf.states[*s], t, end, end - t));
                }
            }
            _ => return Err("usage: report summary|workload|labels|timeline".into()),
        }
        Ok(out)
    }
    fn exec(&mut self, word: &str, rest: &str) {
        let res: Result<Vec<String>, String> = (|| -> Result<Vec<String>, String> {
            match word {
                "actor" => {
                    let w = words(rest);
                    if w.len() != 1 {
                        return Err("usage: actor NAME".into());
                    }
                    self.actor = w[0].to_string();
                    Ok(vec![format!("actor is {}", w[0])])
                }
                "today" => {
                    let w = words(rest);
                    if w.len() != 1 {
                        return Err("usage: today DATE".into());
                    }
                    if !valid_date(w[0]) {
                        return Err(format!("bad date '{}'", w[0]));
                    }
                    self.today = w[0].to_string();
                    Ok(vec![format!("today is {}", w[0])])
                }
                "create" => self.cmd_create(rest).map(|s| vec![s]),
                "edit" => {
                    let t = tokenize(rest)?;
                    if t.is_empty() {
                        return Err("usage: edit ID field=value...".into());
                    }
                    self.do_edit(&t[0], &t[1..]).map(|s| vec![s])
                }
                "label" => {
                    let t = tokenize(rest)?;
                    if t.len() < 2 {
                        return Err("usage: label ID +label -label...".into());
                    }
                    self.do_label(&t[0], &t[1..]).map(|s| vec![s])
                }
                "assign" => {
                    let t = tokenize(rest)?;
                    if t.len() != 2 {
                        return Err("usage: assign ID NAME".into());
                    }
                    self.do_edit(&t[0], &[format!("assignee={}", t[1])]).map(|s| vec![s])
                }
                "move" => {
                    let (a, r) = take_word(rest);
                    let (s, c) = take_word(r);
                    if a.is_empty() || s.is_empty() {
                        return Err("usage: move ID STATE [comment...]".into());
                    }
                    self.do_move(a, s, c.trim()).map(|s| vec![s])
                }
                "comment" => {
                    let (a, r) = take_word(rest);
                    if a.is_empty() || r.trim().is_empty() {
                        return Err("usage: comment ID TEXT".into());
                    }
                    let id = self.live_id(a)?;
                    self.t += 1;
                    let (t, actor) = (self.t, self.actor.clone());
                    let text = r.trim().to_string();
                    let i = self.issues.get_mut(&id).unwrap();
                    i.updated = t;
                    i.comments.push((t, actor, text.clone()));
                    self.addlog(id, format!("comment: {}", text));
                    Ok(vec![format!("commented #{}", id)])
                }
                "delete" => {
                    let w = words(rest);
                    if w.len() != 1 {
                        return Err("usage: delete ID".into());
                    }
                    let id = self.live_id(w[0])?;
                    self.issues.remove(&id);
                    self.t += 1;
                    self.addlog(id, "deleted".into());
                    Ok(vec![format!("deleted #{}", id)])
                }
                "show" => self.cmd_show(rest).map(|s| vec![s]),
                "list" => self.do_list(rest.trim()),
                "log" => self.cmd_log(rest),
                "bulk" => self.cmd_bulk(rest),
                "report" => self.cmd_report(rest),
                _ => Err(format!("unknown command '{}'", word)),
            }
        })();
        self.print_lines(res);
    }
}

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).ok();
    let lines: Vec<&str> = input.split('\n').collect();
    let mut app = App {
        wf: None,
        issues: BTreeMap::new(),
        next_id: 1,
        t: 0,
        actor: "system".into(),
        today: "1970-01-01".into(),
        log: vec![],
        views: BTreeMap::new(),
        out: String::new(),
    };
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i].trim_end();
        i += 1;
        let tl = line.trim_start();
        if tl.is_empty() || tl.starts_with('#') {
            continue;
        }
        app.say(&format!("> {}", line));
        let (word, rest) = take_word(line);
        if word == "workflow" {
            let mut block = vec![];
            while i < lines.len() {
                let l = lines[i].trim();
                i += 1;
                if l == "end" {
                    break;
                }
                block.push(l.to_string());
            }
            if app.next_id > 1 {
                app.say("error: workflow: cannot redefine after issues were created");
                continue;
            }
            match parse_workflow(&block) {
                Ok((w, n)) => {
                    let s = format!("workflow ok: {} states, {} transitions", w.states.len(), n);
                    app.wf = Some(w);
                    app.say(&s);
                }
                Err(e) => app.say(&format!("error: {}", e)),
            }
            continue;
        }
        if word == "view" {
            app.cmd_view(rest);
        } else {
            app.exec(word, rest);
        }
    }
    std::io::stdout().write_all(app.out.as_bytes()).unwrap();
}
