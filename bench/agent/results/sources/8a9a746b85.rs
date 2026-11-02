use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::io::{self, Read, Write};

type R<T> = Result<T, String>;

fn ws(c: char) -> bool {
    c == ' ' || c == '\t'
}

fn words(s: &str) -> Vec<String> {
    s.split_whitespace().map(String::from).collect()
}

fn argn(v: &[String], i: usize) -> String {
    v.get(i).cloned().unwrap_or_default()
}

fn dedup(v: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    v.iter().filter(|x| seen.insert(x.to_string())).cloned().collect()
}

fn join_sep(a: &str, b: &str) -> String {
    if a.is_empty() || b.is_empty() {
        format!("{}{}", a, b)
    } else {
        format!("{} {}", a, b)
    }
}

fn fmt_deps(prefix: &str, normal: &[String], order: &[String]) -> String {
    let mut s = format!("{}:", prefix);
    if !normal.is_empty() {
        s.push(' ');
        s.push_str(&normal.join(" "));
    }
    if !order.is_empty() {
        s.push_str(" | ");
        s.push_str(&order.join(" "));
    }
    s.push('\n');
    s
}

/// Match a `%` pattern (or exact name); returns the stem.
fn pmatch(pat: &str, s: &str) -> Option<String> {
    match pat.find('%') {
        None => {
            if pat == s {
                Some(String::new())
            } else {
                None
            }
        }
        Some(p) => {
            let pre = &pat[..p];
            let suf = &pat[p + 1..];
            if s.len() >= pre.len() + suf.len() && s.starts_with(pre) && s.ends_with(suf) {
                Some(s[pre.len()..s.len() - suf.len()].to_string())
            } else {
                None
            }
        }
    }
}

fn patsubst_words(from: &str, to: &str, text: &str) -> String {
    text.split_whitespace()
        .map(|w| match pmatch(from, w) {
            Some(stem) => {
                if to.contains('%') {
                    to.replacen('%', &stem, 1)
                } else {
                    to.to_string()
                }
            }
            None => w.to_string(),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn split_args(s: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    for c in s.chars() {
        match c {
            '(' | '{' => {
                depth += 1;
                cur.push(c);
            }
            ')' | '}' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                args.push(cur.trim_matches(ws).to_string());
                cur.clear();
            }
            _ => cur.push(c),
        }
    }
    args.push(cur.trim_matches(ws).to_string());
    args
}

fn strip_comment(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\\' && it.peek() == Some(&'#') {
            it.next();
            out.push('#');
        } else if c == '#' {
            break;
        } else {
            out.push(c);
        }
    }
    out
}

/// Byte index of the first `target` outside `$(...)`/`${...}` at or after `start`.
/// For targets other than ';', a top-level ';' stops the search.
fn scan_top(s: &str, target: char, start: usize) -> Option<usize> {
    let cs: Vec<(usize, char)> = s.char_indices().collect();
    let mut depth = 0usize;
    let mut k = 0;
    while k < cs.len() {
        let (pos, c) = cs[k];
        if c == '$' {
            match cs.get(k + 1).map(|x| x.1) {
                Some('(') | Some('{') => {
                    depth += 1;
                    k += 2;
                }
                Some('$') => k += 2,
                _ => k += 1,
            }
            continue;
        }
        if depth > 0 {
            if c == '(' || c == '{' {
                depth += 1;
            } else if c == ')' || c == '}' {
                depth -= 1;
            }
        } else if pos >= start {
            if c == target {
                return Some(pos);
            }
            if c == ';' && target != ';' {
                return None;
            }
        }
        k += 1;
    }
    None
}

fn parse_paren_args(rest: &str) -> Option<(String, String)> {
    let r = rest.trim_matches(ws);
    if r.len() < 2 || !r.starts_with('(') || !r.ends_with(')') {
        return None;
    }
    let inner = &r[1..r.len() - 1];
    let mut depth = 0i32;
    let mut commas = Vec::new();
    for (i, c) in inner.char_indices() {
        match c {
            '(' | '{' => depth += 1,
            ')' | '}' => {
                depth -= 1;
                if depth < 0 {
                    return None;
                }
            }
            ',' if depth == 0 => commas.push(i),
            _ => {}
        }
    }
    if depth != 0 || commas.len() != 1 {
        return None;
    }
    let p = commas[0];
    Some((inner[..p].to_string(), inner[p + 1..].to_string()))
}

fn glob(p: &[char], s: &[char]) -> bool {
    match p.first() {
        None => s.is_empty(),
        Some(&'*') => glob(&p[1..], s) || (!s.is_empty() && s[0] != '/' && glob(p, &s[1..])),
        Some(&'?') => !s.is_empty() && s[0] != '/' && glob(&p[1..], &s[1..]),
        Some(&c) => !s.is_empty() && s[0] == c && glob(&p[1..], &s[1..]),
    }
}

fn file_part(kind: &str, w: &str) -> String {
    let slash = w.rfind('/');
    let comp_start = slash.map_or(0, |p| p + 1);
    let comp = &w[comp_start..];
    match kind {
        "dir" => match slash {
            Some(p) => w[..=p].to_string(),
            None => "./".to_string(),
        },
        "notdir" => comp.to_string(),
        "suffix" => match comp.rfind('.') {
            Some(p) => comp[p..].to_string(),
            None => String::new(),
        },
        _ => match comp.rfind('.') {
            Some(p) => w[..comp_start + p].to_string(),
            None => w.to_string(),
        },
    }
}

const FUNCS: &[&str] = &[
    "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist",
    "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix",
    "addsuffix", "wildcard", "foreach", "if", "info", "error",
];

#[derive(Clone)]
struct Var {
    value: String,
    recursive: bool,
}

#[derive(Clone, Default)]
struct Rule {
    normal: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(usize, String)>,
}

#[derive(Clone)]
struct PatRule {
    pat: String,
    rule: Rule,
}

struct OpenRule {
    lnum: usize,
    targets: Vec<String>,
    rule: Rule,
}

struct Cond {
    parent: bool,
    cond: bool,
    in_else: bool,
    lnum: usize,
}

#[derive(Clone, Default)]
struct Auto {
    target: String,
    first: String,
    all: String,
    order: String,
    newer: String,
    stem: String,
}

#[derive(Clone)]
struct Resolved {
    normal: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(usize, String)>,
    stem: String,
}

#[derive(Default)]
struct Sim {
    files: BTreeMap<String, i64>,
    clock: i64,
    out: String,
    mk_text: String,
    dry: bool,
    // per-request state
    vars: HashMap<String, Var>,
    cmdline: HashMap<String, Var>,
    explicit: HashMap<String, Rule>,
    explicit_order: Vec<String>,
    patterns: Vec<PatRule>,
    phony: Vec<String>,
    phony_set: HashSet<String>,
    conds: Vec<Cond>,
    open: Option<OpenRule>,
    cur_line: Option<usize>,
    bindings: Vec<(String, String)>,
    auto: Option<Auto>,
    expanding: Vec<String>,
    memo: HashMap<String, bool>,
    stack: Vec<String>,
    changed: HashSet<String>,
    recipe_ran: bool,
}

impl Sim {
    fn reset(&mut self) {
        self.dry = false;
        self.vars.clear();
        self.cmdline.clear();
        self.explicit.clear();
        self.explicit_order.clear();
        self.patterns.clear();
        self.phony.clear();
        self.phony_set.clear();
        self.conds.clear();
        self.open = None;
        self.cur_line = None;
        self.bindings.clear();
        self.auto = None;
        self.expanding.clear();
        self.memo.clear();
        self.stack.clear();
        self.changed.clear();
        self.recipe_ran = false;
    }

    fn fatal(&self, msg: &str) -> String {
        match self.cur_line {
            Some(l) => format!("Makefile:{}: *** {}.  Stop.", l, msg),
            None => format!("make: *** {}.  Stop.", msg),
        }
    }

    fn fatal_at(&self, lnum: usize, msg: &str) -> String {
        format!("Makefile:{}: *** {}.  Stop.", lnum, msg)
    }

    fn active(&self) -> bool {
        match self.conds.last() {
            None => true,
            Some(c) => c.parent && (c.cond != c.in_else),
        }
    }

    // ---------- expansion ----------

    fn get_var(&mut self, name: &str) -> R<String> {
        if let Some((_, v)) = self.bindings.iter().rev().find(|(n, _)| n == name) {
            return Ok(v.clone());
        }
        if name.chars().count() == 1 && "@<^?|*".contains(name) {
            return Ok(match &self.auto {
                None => String::new(),
                Some(a) => match name {
                    "@" => a.target.clone(),
                    "<" => a.first.clone(),
                    "^" => a.all.clone(),
                    "?" => a.newer.clone(),
                    "|" => a.order.clone(),
                    "*" => a.stem.clone(),
                    _ => String::new(),
                },
            });
        }
        let var = match self.cmdline.get(name) {
            Some(v) => v.clone(),
            None => match self.vars.get(name) {
                Some(v) => v.clone(),
                None => return Ok(String::new()),
            },
        };
        if !var.recursive {
            return Ok(var.value);
        }
        if self.expanding.iter().any(|n| n == name) {
            return Err(self.fatal(&format!(
                "Recursive variable '{}' references itself (eventually)",
                name
            )));
        }
        self.expanding.push(name.to_string());
        let r = self.expand(&var.value);
        self.expanding.pop();
        r
    }

    fn expand(&mut self, s: &str) -> R<String> {
        let chars: Vec<char> = s.chars().collect();
        let n = chars.len();
        let mut out = String::new();
        let mut i = 0;
        while i < n {
            let c = chars[i];
            if c != '$' {
                out.push(c);
                i += 1;
                continue;
            }
            if i + 1 >= n {
                i += 1;
                continue;
            }
            let d = chars[i + 1];
            match d {
                '$' => {
                    out.push('$');
                    i += 2;
                }
                '(' | '{' => {
                    let close = if d == '(' { ')' } else { '}' };
                    let mut depth = 1;
                    let mut j = i + 2;
                    while j < n {
                        if chars[j] == d {
                            depth += 1;
                        } else if chars[j] == close {
                            depth -= 1;
                            if depth == 0 {
                                break;
                            }
                        }
                        j += 1;
                    }
                    if j >= n {
                        return Err(self.fatal("unterminated variable reference"));
                    }
                    let inner: String = chars[i + 2..j].iter().collect();
                    let v = self.reference(&inner)?;
                    out.push_str(&v);
                    i = j + 1;
                }
                _ => {
                    let v = self.get_var(&d.to_string())?;
                    out.push_str(&v);
                    i += 2;
                }
            }
        }
        Ok(out)
    }

    fn reference(&mut self, inner: &str) -> R<String> {
        let end = inner.find(|c: char| c == ' ' || c == '\t').unwrap_or(inner.len());
        if end < inner.len() && FUNCS.contains(&&inner[..end]) {
            return self.call_fn(&inner[..end], &inner[end + 1..]);
        }
        let t = self.expand(inner)?;
        if let Some(colon) = t.find(':').filter(|&p| p > 0) {
            if let Some(rel) = t[colon + 1..].find('=') {
                let eqp = colon + 1 + rel;
                let name = t[..colon].trim().to_string();
                let from = t[colon + 1..eqp].to_string();
                let to = t[eqp + 1..].to_string();
                let val = self.get_var(&name)?;
                let (f, tt) = if from.contains('%') {
                    (from, to)
                } else {
                    (format!("%{}", from), format!("%{}", to))
                };
                return Ok(patsubst_words(&f, &tt, &val));
            }
        }
        self.get_var(t.trim())
    }

    fn call_fn(&mut self, name: &str, rest: &str) -> R<String> {
        let raw = split_args(rest);
        if name == "if" {
            let c = self.expand(&argn(&raw, 0))?;
            return if !c.trim().is_empty() {
                self.expand(&argn(&raw, 1))
            } else if raw.len() > 2 {
                self.expand(&argn(&raw, 2))
            } else {
                Ok(String::new())
            };
        }
        if name == "foreach" {
            let var = self.expand(&argn(&raw, 0))?.trim().to_string();
            let list = self.expand(&argn(&raw, 1))?;
            let text = argn(&raw, 2);
            let mut res = Vec::new();
            for w in list.split_whitespace() {
                self.bindings.push((var.clone(), w.to_string()));
                let r = self.expand(&text);
                self.bindings.pop();
                res.push(r?);
            }
            return Ok(res.join(" "));
        }
        let mut a: Vec<String> = Vec::with_capacity(raw.len());
        for x in raw.iter() {
            let v = self.expand(x)?;
            a.push(v);
        }
        let g = |i: usize| argn(&a, i);
        Ok(match name {
            "subst" => {
                let (f, t, x) = (g(0), g(1), g(2));
                if f.is_empty() {
                    x
                } else {
                    x.replace(&f, &t)
                }
            }
            "patsubst" => patsubst_words(&g(0), &g(1), &g(2)),
            "strip" => words(&g(0)).join(" "),
            "findstring" => {
                let (f, x) = (g(0), g(1));
                if x.contains(&f) {
                    f
                } else {
                    String::new()
                }
            }
            "filter" | "filter-out" => {
                let pats = words(&g(0));
                let keep = name == "filter";
                words(&g(1))
                    .into_iter()
                    .filter(|w| pats.iter().any(|p| pmatch(p, w).is_some()) == keep)
                    .collect::<Vec<_>>()
                    .join(" ")
            }
            "sort" => {
                let set: BTreeSet<String> = words(&g(0)).into_iter().collect();
                set.into_iter().collect::<Vec<_>>().join(" ")
            }
            "word" => match g(0).trim().parse::<i64>() {
                Ok(n) if n >= 1 => words(&g(1)).get((n - 1) as usize).cloned().unwrap_or_default(),
                _ => String::new(),
            },
            "wordlist" => {
                let s = g(0).trim().parse::<i64>();
                let e = g(1).trim().parse::<i64>();
                let w = words(&g(2));
                match (s, e) {
                    (Ok(s), Ok(e)) if s >= 1 && e >= s && (s as usize) <= w.len() => {
                        let end = std::cmp::min(e as usize, w.len());
                        w[(s as usize - 1)..end].join(" ")
                    }
                    _ => String::new(),
                }
            }
            "words" => words(&g(0)).len().to_string(),
            "firstword" => words(&g(0)).into_iter().next().unwrap_or_default(),
            "lastword" => {
                let mut w = words(&g(0));
                w.pop().unwrap_or_default()
            }
            "dir" | "notdir" | "suffix" | "basename" => words(&g(0))
                .iter()
                .map(|w| file_part(name, w))
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
                .join(" "),
            "addprefix" => {
                let p = g(0);
                words(&g(1)).iter().map(|w| format!("{}{}", p, w)).collect::<Vec<_>>().join(" ")
            }
            "addsuffix" => {
                let p = g(0);
                words(&g(1)).iter().map(|w| format!("{}{}", w, p)).collect::<Vec<_>>().join(" ")
            }
            "wildcard" => {
                let mut res: Vec<String> = Vec::new();
                for p in words(&g(0)) {
                    let pc: Vec<char> = p.chars().collect();
                    for f in self.files.keys() {
                        let fc: Vec<char> = f.chars().collect();
                        if glob(&pc, &fc) {
                            res.push(f.clone());
                        }
                    }
                }
                res.join(" ")
            }
            "info" => {
                self.out.push_str(&g(0));
                self.out.push('\n');
                String::new()
            }
            "error" => return Err(self.fatal(&g(0))),
            _ => String::new(),
        })
    }

    // ---------- parsing ----------

    fn parse(&mut self, text: &str) -> R<()> {
        let phys: Vec<&str> = text.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
        let mut logical: Vec<(usize, String)> = Vec::new();
        let mut i = 0;
        while i < phys.len() {
            let start = i + 1;
            let mut buf = String::new();
            let mut cur = phys[i];
            loop {
                if cur.ends_with('\\') {
                    buf.push_str(cur[..cur.len() - 1].trim_end_matches(ws));
                    if i + 1 < phys.len() {
                        buf.push(' ');
                        i += 1;
                        cur = phys[i].trim_start_matches(ws);
                    } else {
                        i += 1;
                        break;
                    }
                } else {
                    buf.push_str(cur);
                    i += 1;
                    break;
                }
            }
            logical.push((start, buf));
        }

        for (lnum, raw) in logical {
            self.cur_line = Some(lnum);
            if raw.starts_with('\t') {
                let body = raw.trim_start_matches('\t');
                if body.trim().is_empty() || !self.active() {
                    continue;
                }
                if self.open.is_none() {
                    return Err(self.fatal("recipe commences before first target"));
                }
                self.open.as_mut().unwrap().rule.recipe.push((lnum, body.to_string()));
                continue;
            }
            let s = strip_comment(&raw).trim_matches(ws).to_string();
            if s.is_empty() {
                continue;
            }
            let kw_end = s.find(|c: char| c.is_whitespace() || c == '(').unwrap_or(s.len());
            let kw = s[..kw_end].to_string();
            if matches!(kw.as_str(), "ifdef" | "ifndef" | "ifeq" | "ifneq" | "else" | "endif") {
                if self.active() {
                    self.close_rule();
                }
                self.directive(&kw, s[kw_end..].trim(), lnum)?;
                continue;
            }
            if !self.active() {
                continue;
            }
            self.close_rule();
            self.plain_line(&s, lnum)?;
        }
        self.close_rule();
        if let Some(c) = self.conds.last() {
            let l = c.lnum;
            return Err(self.fatal_at(l, "missing 'endif'"));
        }
        Ok(())
    }

    fn directive(&mut self, kw: &str, rest: &str, lnum: usize) -> R<()> {
        let _ = lnum;
        let parent = self.active();
        match kw {
            "ifdef" | "ifndef" => {
                let mut cond = false;
                if parent {
                    let n = self.expand(rest)?.trim().to_string();
                    let def = match self.cmdline.get(&n) {
                        Some(v) => !v.value.is_empty(),
                        None => self.vars.get(&n).map_or(false, |v| !v.value.is_empty()),
                    };
                    cond = if kw == "ifdef" { def } else { !def };
                }
                self.conds.push(Cond { parent, cond, in_else: false, lnum });
            }
            "ifeq" | "ifneq" => {
                let mut cond = false;
                if parent {
                    let Some((a, b)) = parse_paren_args(rest) else {
                        return Err(self.fatal("invalid syntax in conditional"));
                    };
                    let av = self.expand(a.trim())?.trim().to_string();
                    let bv = self.expand(b.trim())?.trim().to_string();
                    cond = (av == bv) == (kw == "ifeq");
                }
                self.conds.push(Cond { parent, cond, in_else: false, lnum });
            }
            "else" => {
                let (empty, in_else) = match self.conds.last() {
                    None => (true, false),
                    Some(c) => (false, c.in_else),
                };
                if empty || in_else {
                    return Err(self.fatal("extraneous 'else'"));
                }
                self.conds.last_mut().unwrap().in_else = true;
            }
            _ => {
                if self.conds.pop().is_none() {
                    return Err(self.fatal("extraneous 'endif'"));
                }
            }
        }
        Ok(())
    }

    fn plain_line(&mut self, s: &str, lnum: usize) -> R<()> {
        let eq = s.find('=');
        let col = scan_top(s, ':', 0);
        let is_assign = match (eq, col) {
            (None, _) => false,
            (Some(_), None) => true,
            (Some(e), Some(c)) => c > e || (e >= 1 && c + 1 == e),
        };
        if is_assign {
            let e = eq.unwrap();
            let bytes = s.as_bytes();
            let (op, name_raw) = if e >= 1 && matches!(bytes[e - 1], b':' | b'?' | b'+') {
                (bytes[e - 1] as char, &s[..e - 1])
            } else {
                ('=', &s[..e])
            };
            let value = s[e + 1..].trim();
            let name = self.expand(name_raw)?.trim().to_string();
            if name.is_empty() {
                return Err(self.fatal("empty variable name"));
            }
            if self.cmdline.contains_key(&name) {
                return Ok(());
            }
            match op {
                '=' => {
                    self.vars.insert(name, Var { value: value.to_string(), recursive: true });
                }
                ':' => {
                    let v = self.expand(value)?;
                    self.vars.insert(name, Var { value: v, recursive: false });
                }
                '?' => {
                    if !self.vars.contains_key(&name) {
                        self.vars.insert(name, Var { value: value.to_string(), recursive: true });
                    }
                }
                _ => match self.vars.get(&name).cloned() {
                    None => {
                        self.vars.insert(name, Var { value: value.to_string(), recursive: true });
                    }
                    Some(old) if !old.recursive => {
                        let v = self.expand(value)?;
                        let nv = join_sep(&old.value, &v);
                        self.vars.insert(name, Var { value: nv, recursive: false });
                    }
                    Some(old) => {
                        let nv = join_sep(&old.value, value);
                        self.vars.insert(name, Var { value: nv, recursive: true });
                    }
                },
            }
            return Ok(());
        }
        if let Some(c) = col {
            let left = &s[..c];
            let (right, cmd) = match scan_top(s, ';', c + 1) {
                Some(p) => (&s[c + 1..p], Some(&s[p + 1..])),
                None => (&s[c + 1..], None),
            };
            let targets = words(&self.expand(left)?);
            let ptext = self.expand(right)?;
            let (normal, order) = match ptext.find('|') {
                Some(p) => (words(&ptext[..p]), words(&ptext[p + 1..])),
                None => (words(&ptext), Vec::new()),
            };
            let mut recipe = Vec::new();
            if let Some(cmdtext) = cmd {
                if !cmdtext.trim().is_empty() {
                    recipe.push((lnum, cmdtext.to_string()));
                }
            }
            for t in &targets {
                if !t.contains('%') && !self.explicit.contains_key(t) {
                    self.explicit_order.push(t.clone());
                    self.explicit.insert(t.clone(), Rule::default());
                }
            }
            self.open = Some(OpenRule {
                lnum,
                targets,
                rule: Rule { normal, order, recipe },
            });
            return Ok(());
        }
        let v = self.expand(s)?;
        if v.trim().is_empty() {
            return Ok(());
        }
        Err(self.fatal("missing separator"))
    }

    fn close_rule(&mut self) {
        let o = match self.open.take() {
            Some(o) => o,
            None => return,
        };
        for t in o.targets.iter() {
            if t.contains('%') {
                self.patterns.push(PatRule { pat: t.clone(), rule: o.rule.clone() });
                continue;
            }
            if t.as_str() == ".PHONY" {
                for p in o.rule.normal.iter().chain(o.rule.order.iter()) {
                    if self.phony_set.insert(p.clone()) {
                        self.phony.push(p.clone());
                    }
                }
            }
            let e = self.explicit.entry(t.clone()).or_default();
            if !o.rule.recipe.is_empty() {
                if !e.recipe.is_empty() {
                    self.out.push_str(&format!(
                        "Makefile:{}: warning: overriding recipe for target '{}'\n",
                        o.lnum, t
                    ));
                }
                e.recipe = o.rule.recipe.clone();
            }
            e.normal.extend(o.rule.normal.iter().cloned());
            e.order.extend(o.rule.order.iter().cloned());
        }
    }

    // ---------- resolution ----------

    fn find_pattern(&self, t: &str, depth: usize) -> Option<(usize, String)> {
        for (idx, pr) in self.patterns.iter().enumerate() {
            if pr.rule.recipe.is_empty() {
                continue;
            }
            let stem = match pmatch(&pr.pat, t) {
                Some(s) if !s.is_empty() => s,
                _ => continue,
            };
            let ok = pr
                .rule
                .normal
                .iter()
                .chain(pr.rule.order.iter())
                .all(|p| self.can_make(&p.replacen('%', &stem, 1), depth));
            if ok {
                return Some((idx, stem));
            }
        }
        None
    }

    fn can_make(&self, name: &str, depth: usize) -> bool {
        if self.files.contains_key(name) || self.explicit.contains_key(name) || self.phony_set.contains(name) {
            return true;
        }
        if depth >= 8 {
            return false;
        }
        self.find_pattern(name, depth + 1).is_some()
    }

    fn resolve(&self, t: &str) -> Option<Resolved> {
        if let Some(r) = self.explicit.get(t) {
            if !r.recipe.is_empty() {
                return Some(Resolved {
                    normal: r.normal.clone(),
                    order: r.order.clone(),
                    recipe: r.recipe.clone(),
                    stem: String::new(),
                });
            }
        }
        if let Some((idx, stem)) = self.find_pattern(t, 0) {
            let pr = &self.patterns[idx].rule;
            let mut normal: Vec<String> = pr.normal.iter().map(|p| p.replacen('%', &stem, 1)).collect();
            let mut order: Vec<String> = pr.order.iter().map(|p| p.replacen('%', &stem, 1)).collect();
            if let Some(r) = self.explicit.get(t) {
                normal.extend(r.normal.iter().cloned());
                order.extend(r.order.iter().cloned());
            }
            return Some(Resolved { normal, order, recipe: pr.recipe.clone(), stem });
        }
        if let Some(r) = self.explicit.get(t) {
            return Some(Resolved {
                normal: r.normal.clone(),
                order: r.order.clone(),
                recipe: Vec::new(),
                stem: String::new(),
            });
        }
        None
    }

    fn default_goal(&self) -> Option<String> {
        self.explicit_order.iter().find(|n| !n.starts_with('.')).cloned()
    }

    // ---------- building ----------

    fn update(&mut self, t: &str, needed_by: Option<&str>) -> R<bool> {
        if let Some(&r) = self.memo.get(t) {
            return Ok(r);
        }
        if let Some(pos) = self.stack.iter().position(|x| x.as_str() == t) {
            let mut cyc: Vec<String> = self.stack[pos..].to_vec();
            cyc.push(t.to_string());
            return Err(format!(
                "make: *** Circular dependency detected: {}.  Stop.",
                cyc.join(" -> ")
            ));
        }
        let res = match self.resolve(t) {
            Some(r) => r,
            None => {
                if self.files.contains_key(t) {
                    self.memo.insert(t.to_string(), false);
                    return Ok(false);
                }
                if self.phony_set.contains(t) {
                    self.memo.insert(t.to_string(), true);
                    self.changed.insert(t.to_string());
                    return Ok(true);
                }
                return Err(match needed_by {
                    Some(n) => format!("make: *** No rule to make target '{}', needed by '{}'.  Stop.", t, n),
                    None => format!("make: *** No rule to make target '{}'.  Stop.", t),
                });
            }
        };
        let old = self.files.get(t).copied();
        self.stack.push(t.to_string());
        let mut any_changed = false;
        let mut newer = false;
        for p in dedup(&res.normal) {
            if self.update(&p, Some(t))? {
                any_changed = true;
            }
            if let (Some(o), Some(pm)) = (old, self.files.get(&p).copied()) {
                if pm > o {
                    newer = true;
                }
            }
        }
        for p in dedup(&res.order) {
            self.update(&p, Some(t))?;
        }
        self.stack.pop();
        let must = self.phony_set.contains(t) || !self.files.contains_key(t) || any_changed || newer;
        let mut changed = false;
        if must {
            changed = true;
            if !res.recipe.is_empty() {
                self.run_recipe(t, &res, old)?;
            }
        }
        self.memo.insert(t.to_string(), changed);
        if changed {
            self.changed.insert(t.to_string());
        }
        Ok(changed)
    }

    fn run_recipe(&mut self, t: &str, res: &Resolved, old: Option<i64>) -> R<()> {
        self.recipe_ran = true;
        let norm = dedup(&res.normal);
        let ord = dedup(&res.order);
        let t_mtime = old.unwrap_or(0);
        let newer: Vec<String> = norm
            .iter()
            .filter(|p| {
                old.is_none()
                    || self.changed.contains(p.as_str())
                    || self.files.get(p.as_str()).map_or(false, |&m| m > t_mtime)
            })
            .cloned()
            .collect();
        let auto = Auto {
            target: t.to_string(),
            first: res.normal.first().cloned().unwrap_or_default(),
            all: norm.join(" "),
            order: ord.join(" "),
            newer: newer.join(" "),
            stem: res.stem.clone(),
        };
        for (lnum, text) in res.recipe.iter() {
            self.cur_line = Some(*lnum);
            self.auto = Some(auto.clone());
            let r = self.run_line(t, *lnum, text);
            self.auto = None;
            r?;
        }
        if !self.dry && !self.phony_set.contains(t) {
            self.clock += 1;
            let c = self.clock;
            self.files.insert(t.to_string(), c);
        }
        Ok(())
    }

    fn run_line(&mut self, t: &str, lnum: usize, text: &str) -> R<()> {
        let ex = self.expand(text)?;
        let mut body: &str = ex.trim();
        let mut ignore = false;
        let mut silent = false;
        loop {
            match body.chars().next() {
                Some('@') => silent = true,
                Some('-') => ignore = true,
                Some('+') | Some(' ') | Some('\t') => {}
                _ => break,
            }
            body = &body[1..];
        }
        let cmd = body.trim();
        if cmd.is_empty() {
            return Ok(());
        }
        if self.dry || !silent {
            self.out.push_str(cmd);
            self.out.push('\n');
        }
        if self.dry {
            return Ok(());
        }
        let status = self.simulate(cmd);
        if status != 0 {
            if ignore {
                self.out.push_str(&format!(
                    "make: [Makefile:{}: {}] Error {} (ignored)\n",
                    lnum, t, status
                ));
            } else {
                return Err(format!("make: *** [Makefile:{}: {}] Error {}", lnum, t, status));
            }
        }
        Ok(())
    }

    fn simulate(&mut self, cmd: &str) -> i64 {
        let w: Vec<&str> = cmd.split_whitespace().collect();
        let args = &w[1..];
        match w[0] {
            "false" => 1,
            "exit" => match args.first() {
                None => 0,
                Some(n) => n.parse::<i64>().unwrap_or(2),
            },
            "touch" => {
                for f in args.iter().filter(|a| !a.starts_with('-')) {
                    self.clock += 1;
                    let c = self.clock;
                    self.files.insert(f.to_string(), c);
                }
                0
            }
            "rm" => {
                for f in args.iter().filter(|a| !a.starts_with('-')) {
                    self.files.remove(*f);
                }
                0
            }
            "cp" if args.len() == 2 => {
                let (src, dst) = (args[0], args[1]);
                if !self.files.contains_key(src) {
                    self.out.push_str(&format!(
                        "cp: cannot stat '{}': No such file or directory\n",
                        src
                    ));
                    1
                } else {
                    self.clock += 1;
                    let c = self.clock;
                    self.files.insert(dst.to_string(), c);
                    0
                }
            }
            "echo" => {
                let parts: Vec<String> = args
                    .iter()
                    .map(|a| a.chars().filter(|c| *c != '\'' && *c != '"').collect::<String>())
                    .collect();
                self.out.push_str(&parts.join(" "));
                self.out.push('\n');
                0
            }
            _ => 0,
        }
    }

    fn deps_visit(
        &mut self,
        t: &str,
        stack: &mut Vec<String>,
        visited: &mut HashSet<String>,
        lines: &mut Vec<String>,
    ) -> R<()> {
        let res = match self.resolve(t) {
            Some(r) => r,
            None => return Ok(()),
        };
        let mut children = dedup(&res.normal);
        children.extend(dedup(&res.order));
        for c in children {
            if let Some(pos) = stack.iter().position(|x| *x == c) {
                let mut cyc: Vec<String> = stack[pos..].to_vec();
                cyc.push(c.clone());
                return Err(format!(
                    "make: *** Circular dependency detected: {}.  Stop.",
                    cyc.join(" -> ")
                ));
            }
            if visited.contains(&c) {
                continue;
            }
            stack.push(c.clone());
            self.deps_visit(&c, stack, visited, lines)?;
            stack.pop();
            visited.insert(c.clone());
            lines.push(c);
        }
        Ok(())
    }

    fn list_targets(&mut self) {
        if let Some(d) = self.default_goal() {
            self.out.push_str(&format!("default: {}\n", d));
        }
        for name in self.explicit_order.clone() {
            let r = self.explicit.get(&name).cloned().unwrap_or_default();
            let line = fmt_deps(&name, &r.normal, &r.order);
            self.out.push_str(&line);
        }
        for pr in self.patterns.clone() {
            let line = fmt_deps(&format!("pattern {}", pr.pat), &pr.rule.normal, &pr.rule.order);
            self.out.push_str(&line);
        }
        if !self.phony.is_empty() {
            self.out.push_str(&format!("phony: {}\n", self.phony.join(" ")));
        }
    }

    fn make_request(&mut self, kind: &str, args: &[&str]) -> R<()> {
        self.reset();
        let mut targets: Vec<String> = Vec::new();
        for a in args.iter() {
            let a: &str = a;
            match a.find('=') {
                Some(p) if p > 0 => {
                    self.cmdline.insert(
                        a[..p].to_string(),
                        Var { value: a[p + 1..].to_string(), recursive: true },
                    );
                }
                _ => targets.push(a.to_string()),
            }
        }
        self.dry = kind == "dry";
        let mt = self.mk_text.clone();
        self.parse(&mt)?;
        match kind {
            "targets" => self.list_targets(),
            "deps" => {
                if targets.len() != 1 {
                    self.out.push_str("usage: deps TARGET\n");
                    return Ok(());
                }
                let t = targets[0].clone();
                let mut lines = Vec::new();
                let mut visited = HashSet::new();
                let mut stack = vec![t.clone()];
                self.deps_visit(&t, &mut stack, &mut visited, &mut lines)?;
                if lines.is_empty() {
                    self.out.push_str("(no prerequisites)\n");
                } else {
                    for l in lines {
                        self.out.push_str(&l);
                        self.out.push('\n');
                    }
                }
            }
            _ => {
                let goals = if targets.is_empty() {
                    match self.default_goal() {
                        Some(d) => vec![d],
                        None => return Err("make: *** No targets.  Stop.".to_string()),
                    }
                } else {
                    targets
                };
                for g in goals {
                    self.recipe_ran = false;
                    self.update(&g, None)?;
                    if !self.recipe_ran {
                        let has = self.resolve(&g).map_or(false, |r| !r.recipe.is_empty());
                        if has || (self.files.contains_key(&g) && !self.phony_set.contains(&g)) {
                            self.out.push_str(&format!("make: '{}' is up to date.\n", g));
                        } else {
                            self.out.push_str(&format!("make: Nothing to be done for '{}'.\n", g));
                        }
                    }
                }
            }
        }
        Ok(())
    }

    fn expand_request(&mut self, text: &str) -> R<String> {
        self.reset();
        let mt = self.mk_text.clone();
        self.parse(&mt)?;
        self.cur_line = None;
        self.expand(text)
    }

    fn handle(&mut self, line: &str) {
        let ws_: Vec<&str> = line.split_whitespace().collect();
        let cmd = ws_[0];
        match cmd {
            "build" | "dry" | "deps" | "targets" => {
                if let Err(e) = self.make_request(cmd, &ws_[1..]) {
                    self.out.push_str(&e);
                    self.out.push('\n');
                }
            }
            "expand" => {
                let text = line[cmd.len()..].trim().to_string();
                match self.expand_request(&text) {
                    Ok(v) => {
                        self.out.push_str(&format!("[{}]\n", v));
                    }
                    Err(e) => {
                        self.out.push_str(&e);
                        self.out.push('\n');
                    }
                }
            }
            "files" => {
                if self.files.is_empty() {
                    self.out.push_str("(no files)\n");
                } else {
                    for (n, m) in self.files.iter() {
                        self.out.push_str(&format!("{} {}\n", n, m));
                    }
                }
            }
            "touch" => match ws_.len() {
                2 => {
                    self.clock += 1;
                    let c = self.clock;
                    self.files.insert(ws_[1].to_string(), c);
                }
                3 => match ws_[2].parse::<i64>() {
                    Ok(n) => {
                        self.files.insert(ws_[1].to_string(), n);
                        if n > self.clock {
                            self.clock = n;
                        }
                    }
                    Err(_) => self.out.push_str("bad request\n"),
                },
                _ => self.out.push_str("bad request\n"),
            },
            "rm" => {
                for f in &ws_[1..] {
                    self.files.remove(*f);
                }
            }
            _ => {
                self.out.push_str(&format!("unknown request: {}\n", cmd));
            }
        }
    }
}

fn main() {
    let mut raw = Vec::new();
    let _ = io::stdin().read_to_end(&mut raw);
    let input = String::from_utf8_lossy(&raw).into_owned();
    let lines: Vec<&str> = input
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();

    let mut seps = Vec::new();
    for (i, l) in lines.iter().enumerate() {
        if *l == "====" {
            seps.push(i);
            if seps.len() == 2 {
                break;
            }
        }
    }
    let (mk_lines, table, reqs): (&[&str], &[&str], &[&str]) = match seps.len() {
        0 => (&lines[..], &[], &[]),
        1 => (&lines[..seps[0]], &lines[seps[0] + 1..], &[]),
        _ => (&lines[..seps[0]], &lines[seps[0] + 1..seps[1]], &lines[seps[1] + 1..]),
    };

    let mut sim = Sim::default();
    sim.mk_text = mk_lines.join("\n");
    for l in table {
        let f: Vec<&str> = l.split_whitespace().collect();
        if f.len() == 2 {
            if let Ok(m) = f[1].parse::<i64>() {
                if m >= 0 {
                    sim.files.insert(f[0].to_string(), m);
                }
            }
        }
    }
    sim.clock = sim.files.values().copied().max().unwrap_or(0);

    for req in reqs {
        let t = req.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        sim.out.push_str("> ");
        sim.out.push_str(req.trim_end());
        sim.out.push('\n');
        sim.handle(t);
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(sim.out.as_bytes());
    let _ = lock.flush();
}
