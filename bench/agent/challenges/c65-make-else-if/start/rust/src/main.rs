use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{Read, Write};

#[derive(Clone)]
struct Var {
    value: String,
    simple: bool,
}

#[derive(Default, Clone)]
struct Explicit {
    prereqs: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(String, usize)>,
}

#[derive(Clone)]
struct Pattern {
    pat: String,
    prereqs: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(String, usize)>,
}

struct OpenRule {
    line: usize,
    targets: Vec<String>,
    prereqs: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(String, usize)>,
}

struct Resolved {
    prereqs: Vec<String>,
    order: Vec<String>,
    recipe: Vec<(String, usize)>,
    stem: String,
}

#[derive(Default)]
struct Auto {
    target: String,
    first: String,
    all: String,
    newer: String,
    order: String,
    stem: String,
}

struct Cond {
    line: usize,
    parent: bool,
    cur: bool,
    cond: bool,
    seen_else: bool,
}

#[derive(Default)]
struct M {
    files: BTreeMap<String, i64>,
    clock: i64,
    out: String,
    vars: HashMap<String, Var>,
    cmdvars: HashSet<String>,
    explicit: HashMap<String, Explicit>,
    order: Vec<String>,
    patterns: Vec<Pattern>,
    phony: Vec<String>,
    default: Option<String>,
    cur_line: Option<usize>,
    auto: Option<Auto>,
    foreach: Vec<(String, String)>,
    expanding: Vec<String>,
    dry: bool,
    memo: HashMap<String, bool>,
    stack: Vec<String>,
    recipes_run: usize,
}

type R<T> = Result<T, String>;

fn find_close(b: &[u8], open: usize) -> Option<usize> {
    let (o, c) = if b[open] == b'(' { (b'(', b')') } else { (b'{', b'}') };
    let mut d = 0;
    let mut i = open;
    while i < b.len() {
        if b[i] == o {
            d += 1;
        } else if b[i] == c {
            d -= 1;
            if d == 0 {
                return Some(i);
            }
        }
        i += 1;
    }
    None
}

fn find_col(line: &str) -> Option<usize> {
    let b = line.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'$' {
            if i + 1 < b.len() {
                let n = b[i + 1];
                if n == b'(' || n == b'{' {
                    match find_close(b, i + 1) {
                        Some(j) => i = j + 1,
                        None => return None,
                    }
                } else {
                    i += 2;
                }
            } else {
                i += 1;
            }
            continue;
        }
        if c == b';' {
            return None;
        }
        if c == b':' {
            return Some(i);
        }
        i += 1;
    }
    None
}

fn split_args(s: &str) -> Vec<String> {
    let mut v = Vec::new();
    let mut d = 0i32;
    let mut cur = String::new();
    for ch in s.chars() {
        match ch {
            '(' | '{' => {
                d += 1;
                cur.push(ch)
            }
            ')' | '}' => {
                if d > 0 {
                    d -= 1;
                }
                cur.push(ch)
            }
            ',' if d == 0 => {
                v.push(cur.trim_matches(|c| c == ' ' || c == '\t').to_string());
                cur.clear();
            }
            _ => cur.push(ch),
        }
    }
    v.push(cur.trim_matches(|c| c == ' ' || c == '\t').to_string());
    v
}

fn words(s: &str) -> Vec<String> {
    s.split(|c| c == ' ' || c == '\t' || c == '\n' || c == '\r')
        .filter(|w| !w.is_empty())
        .map(|w| w.to_string())
        .collect()
}

fn pat_match(pat: &str, w: &str) -> Option<String> {
    match pat.find('%') {
        None => {
            if pat == w {
                Some(String::new())
            } else {
                None
            }
        }
        Some(p) => {
            let pre = &pat[..p];
            let suf = &pat[p + 1..];
            if w.len() >= pre.len() + suf.len() && w.starts_with(pre) && w.ends_with(suf) {
                Some(w[pre.len()..w.len() - suf.len()].to_string())
            } else {
                None
            }
        }
    }
}

fn subst_pct(rep: &str, stem: &str) -> String {
    match rep.find('%') {
        None => rep.to_string(),
        Some(p) => format!("{}{}{}", &rep[..p], stem, &rep[p + 1..]),
    }
}

fn patsubst(pat: &str, rep: &str, text: &str) -> String {
    words(text)
        .iter()
        .map(|w| match pat_match(pat, w) {
            Some(st) => subst_pct(rep, &st),
            None => w.clone(),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn glob(p: &[char], s: &[char]) -> bool {
    if p.is_empty() {
        return s.is_empty();
    }
    match p[0] {
        '*' => {
            let mut k = 0;
            loop {
                if glob(&p[1..], &s[k..]) {
                    return true;
                }
                if k < s.len() && s[k] != '/' {
                    k += 1;
                } else {
                    return false;
                }
            }
        }
        '?' => !s.is_empty() && s[0] != '/' && glob(&p[1..], &s[1..]),
        c => !s.is_empty() && s[0] == c && glob(&p[1..], &s[1..]),
    }
}

fn dedup(v: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut r = Vec::new();
    for x in v {
        if seen.insert(x.clone()) {
            r.push(x.clone());
        }
    }
    r
}

const FUNCS: &[&str] = &[
    "subst", "patsubst", "strip", "findstring", "filter", "filter-out", "sort", "word", "wordlist",
    "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "addprefix",
    "addsuffix", "wildcard", "foreach", "if", "info", "error",
];

impl M {
    fn fatal(&self, msg: &str) -> String {
        match self.cur_line {
            Some(n) => format!("Makefile:{}: *** {}.  Stop.", n, msg),
            None => format!("make: *** {}.  Stop.", msg),
        }
    }

    fn expand(&mut self, s: &str) -> R<String> {
        let b = s.as_bytes();
        let mut out = String::new();
        let mut i = 0;
        let mut start = 0;
        while i < b.len() {
            if b[i] != b'$' {
                i += 1;
                continue;
            }
            out.push_str(&s[start..i]);
            if i + 1 >= b.len() {
                i += 1;
                start = i;
                break;
            }
            let n = b[i + 1];
            if n == b'$' {
                out.push('$');
                i += 2;
            } else if n == b'(' || n == b'{' {
                let j = match find_close(b, i + 1) {
                    Some(j) => j,
                    None => return Err(self.fatal("unterminated variable reference")),
                };
                let inner = &s[i + 2..j];
                let r = self.expand_ref(inner)?;
                out.push_str(&r);
                i = j + 1;
            } else {
                let ch = s[i + 1..].chars().next().unwrap();
                let r = self.lookup(&ch.to_string())?;
                out.push_str(&r);
                i += 1 + ch.len_utf8();
            }
            start = i;
        }
        if start < s.len() {
            out.push_str(&s[start..]);
        }
        Ok(out)
    }

    fn expand_ref(&mut self, inner: &str) -> R<String> {
        if let Some(p) = inner.find(|c| c == ' ' || c == '\t') {
            let name = &inner[..p];
            if FUNCS.contains(&name) {
                return self.call(name, &inner[p..]);
            }
        }
        let name = self.expand(inner)?;
        let name = name.trim_matches(|c| c == ' ' || c == '\t' || c == '\n').to_string();
        if let Some(c) = name.char_indices().skip(1).find(|(_, c)| *c == ':').map(|x| x.0) {
            if let Some(e) = name[c + 1..].find('=') {
                let var = &name[..c];
                let from = &name[c + 1..c + 1 + e];
                let to = &name[c + 2 + e..];
                let val = self.lookup(var)?;
                let (f, t) = if from.contains('%') {
                    (from.to_string(), to.to_string())
                } else {
                    (format!("%{}", from), format!("%{}", to))
                };
                return Ok(patsubst(&f, &t, &val));
            }
        }
        self.lookup(&name)
    }

    fn lookup(&mut self, name: &str) -> R<String> {
        for (k, v) in self.foreach.iter().rev() {
            if k == name {
                return Ok(v.clone());
            }
        }
        if let Some(a) = &self.auto {
            match name {
                "@" => return Ok(a.target.clone()),
                "<" => return Ok(a.first.clone()),
                "^" => return Ok(a.all.clone()),
                "?" => return Ok(a.newer.clone()),
                "|" => return Ok(a.order.clone()),
                "*" => return Ok(a.stem.clone()),
                _ => {}
            }
        }
        let v = match self.vars.get(name) {
            Some(v) => v.clone(),
            None => return Ok(String::new()),
        };
        if v.simple {
            return Ok(v.value);
        }
        if self.expanding.iter().any(|x| x == name) {
            return Err(self.fatal(&format!(
                "Recursive variable '{}' references itself (eventually)",
                name
            )));
        }
        self.expanding.push(name.to_string());
        let r = self.expand(&v.value);
        self.expanding.pop();
        r
    }

    fn call(&mut self, name: &str, rest: &str) -> R<String> {
        let raw = split_args(rest.trim_start_matches(|c| c == ' ' || c == '\t'));
        let get = |i: usize| -> String { raw.get(i).cloned().unwrap_or_default() };
        match name {
            "foreach" => {
                let var = self.expand(&get(0))?.trim().to_string();
                let list = self.expand(&get(1))?;
                let text = get(2);
                let mut res = Vec::new();
                for w in words(&list) {
                    self.foreach.push((var.clone(), w));
                    let r = self.expand(&text);
                    self.foreach.pop();
                    res.push(r?);
                }
                return Ok(res.join(" "));
            }
            "if" => {
                let c = self.expand(&get(0))?;
                if !c.trim().is_empty() {
                    return self.expand(&get(1));
                } else {
                    return self.expand(&get(2));
                }
            }
            "info" => {
                let t = self.expand(&get(0))?;
                self.out.push_str(&t);
                self.out.push('\n');
                return Ok(String::new());
            }
            "error" => {
                let t = self.expand(&get(0))?;
                return Err(self.fatal(&t));
            }
            _ => {}
        }
        let nargs = match name {
            "subst" | "patsubst" | "wordlist" => 3,
            "findstring" | "filter" | "filter-out" | "word" | "addprefix" | "addsuffix" => 2,
            _ => 1,
        };
        let mut a = Vec::new();
        for i in 0..nargs {
            a.push(self.expand(&get(i))?);
        }
        let ws = |s: &str| words(s);
        Ok(match name {
            "subst" => {
                if a[0].is_empty() {
                    a[2].clone()
                } else {
                    a[2].replace(&a[0], &a[1])
                }
            }
            "patsubst" => patsubst(&a[0], &a[1], &a[2]),
            "strip" => ws(&a[0]).join(" "),
            "findstring" => {
                if a[1].contains(&a[0]) {
                    a[0].clone()
                } else {
                    String::new()
                }
            }
            "filter" | "filter-out" => {
                let pats = ws(&a[0]);
                let keep = name == "filter";
                ws(&a[1])
                    .into_iter()
                    .filter(|w| pats.iter().any(|p| pat_match(p, w).is_some()) == keep)
                    .collect::<Vec<_>>()
                    .join(" ")
            }
            "sort" => {
                let mut v = ws(&a[0]);
                v.sort();
                v.dedup();
                v.join(" ")
            }
            "word" => {
                let w = ws(&a[1]);
                match a[0].trim().parse::<i64>() {
                    Ok(n) if n >= 1 && (n as usize) <= w.len() => w[n as usize - 1].clone(),
                    _ => String::new(),
                }
            }
            "wordlist" => {
                let w = ws(&a[2]);
                match (a[0].trim().parse::<i64>(), a[1].trim().parse::<i64>()) {
                    (Ok(s), Ok(e)) if s >= 1 && e >= s && (s as usize) <= w.len() => {
                        let e = (e as usize).min(w.len());
                        w[s as usize - 1..e].join(" ")
                    }
                    _ => String::new(),
                }
            }
            "words" => ws(&a[0]).len().to_string(),
            "firstword" => ws(&a[0]).first().cloned().unwrap_or_default(),
            "lastword" => ws(&a[0]).last().cloned().unwrap_or_default(),
            "dir" => ws(&a[0])
                .iter()
                .map(|w| match w.rfind('/') {
                    Some(p) => w[..=p].to_string(),
                    None => "./".to_string(),
                })
                .collect::<Vec<_>>()
                .join(" "),
            "notdir" => ws(&a[0])
                .iter()
                .map(|w| match w.rfind('/') {
                    Some(p) => w[p + 1..].to_string(),
                    None => w.clone(),
                })
                .collect::<Vec<_>>()
                .join(" "),
            "suffix" => ws(&a[0])
                .iter()
                .filter_map(|w| {
                    let base = w.rfind('/').map(|p| p + 1).unwrap_or(0);
                    w[base..].rfind('.').map(|d| w[base + d..].to_string())
                })
                .collect::<Vec<_>>()
                .join(" "),
            "basename" => ws(&a[0])
                .iter()
                .map(|w| {
                    let base = w.rfind('/').map(|p| p + 1).unwrap_or(0);
                    match w[base..].rfind('.') {
                        Some(d) => w[..base + d].to_string(),
                        None => w.clone(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" "),
            "addprefix" => ws(&a[1])
                .iter()
                .map(|w| format!("{}{}", a[0], w))
                .collect::<Vec<_>>()
                .join(" "),
            "addsuffix" => ws(&a[1])
                .iter()
                .map(|w| format!("{}{}", w, a[0]))
                .collect::<Vec<_>>()
                .join(" "),
            "wildcard" => {
                let mut res = Vec::new();
                for p in ws(&a[0]) {
                    if p.contains('*') || p.contains('?') {
                        let pc: Vec<char> = p.chars().collect();
                        for f in self.files.keys() {
                            let fc: Vec<char> = f.chars().collect();
                            if glob(&pc, &fc) {
                                res.push(f.clone());
                            }
                        }
                    } else if self.files.contains_key(&p) {
                        res.push(p.clone());
                    }
                }
                res.join(" ")
            }
            _ => String::new(),
        })
    }

    fn reset_parse(&mut self) {
        self.vars.clear();
        self.cmdvars.clear();
        self.explicit.clear();
        self.order.clear();
        self.patterns.clear();
        self.phony.clear();
        self.default = None;
        self.cur_line = None;
        self.auto = None;
        self.foreach.clear();
        self.expanding.clear();
        self.memo.clear();
        self.stack.clear();
        self.recipes_run = 0;
    }

    fn close_rule(&mut self, open: &mut Option<OpenRule>) {
        let r = match open.take() {
            Some(r) => r,
            None => return,
        };
        if r.targets.len() == 1 && r.targets[0] == ".PHONY" {
            for p in &r.prereqs {
                if !self.phony.contains(p) {
                    self.phony.push(p.clone());
                }
            }
            return;
        }
        for t in &r.targets {
            if t.contains('%') {
                self.patterns.push(Pattern {
                    pat: t.clone(),
                    prereqs: r.prereqs.clone(),
                    order: r.order.clone(),
                    recipe: r.recipe.clone(),
                });
            } else {
                if !self.explicit.contains_key(t) {
                    self.order.push(t.clone());
                    if self.default.is_none() && !t.starts_with('.') {
                        self.default = Some(t.clone());
                    }
                }
                let e = self.explicit.entry(t.clone()).or_default();
                e.prereqs.extend(r.prereqs.iter().cloned());
                e.order.extend(r.order.iter().cloned());
                if !r.recipe.is_empty() {
                    let warn = !e.recipe.is_empty();
                    e.recipe = r.recipe.clone();
                    if warn {
                        self.out.push_str(&format!(
                            "Makefile:{}: warning: overriding recipe for target '{}'\n",
                            r.line, t
                        ));
                    }
                }
            }
        }
    }

    fn parse(&mut self, mk: &str) -> R<()> {
        let lines: Vec<&str> = mk.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
        let mut conds: Vec<Cond> = Vec::new();
        let mut open: Option<OpenRule> = None;
        let mut i = 0;
        while i < lines.len() {
            let lineno = i + 1;
            let mut cur = lines[i].to_string();
            while cur.ends_with('\\') {
                cur.pop();
                let t = cur.trim_end_matches(|c| c == ' ' || c == '\t').len();
                cur.truncate(t);
                if i + 1 < lines.len() {
                    i += 1;
                    cur.push(' ');
                    cur.push_str(lines[i].trim_start_matches(|c| c == ' ' || c == '\t'));
                } else {
                    break;
                }
            }
            i += 1;
            self.cur_line = Some(lineno);
            let active = conds.last().map(|c| c.cur).unwrap_or(true);
            if cur.starts_with('\t') {
                let text = cur.trim_start_matches('\t');
                if text.trim().is_empty() {
                    continue;
                }
                if !active {
                    continue;
                }
                match &mut open {
                    Some(r) => r.recipe.push((text.to_string(), lineno)),
                    None => return Err(self.fatal("recipe commences before first target")),
                }
                continue;
            }
            // strip comment
            let mut line = String::new();
            {
                let cs: Vec<char> = cur.chars().collect();
                let mut k = 0;
                while k < cs.len() {
                    if cs[k] == '\\' && k + 1 < cs.len() && cs[k + 1] == '#' {
                        line.push('#');
                        k += 2;
                        continue;
                    }
                    if cs[k] == '#' {
                        break;
                    }
                    line.push(cs[k]);
                    k += 1;
                }
            }
            let line = line.trim_matches(|c| c == ' ' || c == '\t').to_string();
            if line.is_empty() {
                continue;
            }
            let first = line.split(|c| c == ' ' || c == '\t').next().unwrap();
            let rest = line[first.len()..].trim_matches(|c| c == ' ' || c == '\t').to_string();
            match first {
                "ifdef" | "ifndef" | "ifeq" | "ifneq" => {
                    self.close_rule(&mut open);
                    let mut val = false;
                    if active {
                        if first == "ifdef" || first == "ifndef" {
                            let n = self.expand(&rest)?;
                            let n = n.trim().to_string();
                            let d = self.vars.get(&n).map(|v| !v.value.is_empty()).unwrap_or(false);
                            val = if first == "ifdef" { d } else { !d };
                        } else {
                            if !(rest.starts_with('(') && rest.ends_with(')') && rest.len() >= 2) {
                                return Err(self.fatal("invalid syntax in conditional"));
                            }
                            let inner = &rest[1..rest.len() - 1];
                            let parts = split_args_raw(inner);
                            if parts.len() != 2 {
                                return Err(self.fatal("invalid syntax in conditional"));
                            }
                            let l = self.expand(parts[0].trim())?;
                            let r = self.expand(parts[1].trim())?;
                            let eq = l.trim() == r.trim();
                            val = if first == "ifeq" { eq } else { !eq };
                        }
                    }
                    conds.push(Cond { line: lineno, parent: active, cur: active && val, cond: val, seen_else: false });
                    continue;
                }
                "else" => {
                    self.close_rule(&mut open);
                    match conds.last_mut() {
                        Some(c) if !c.seen_else => {
                            c.seen_else = true;
                            c.cur = c.parent && !c.cond;
                        }
                        _ => return Err(self.fatal("extraneous 'else'")),
                    }
                    continue;
                }
                "endif" => {
                    self.close_rule(&mut open);
                    if conds.pop().is_none() {
                        return Err(self.fatal("extraneous 'endif'"));
                    }
                    continue;
                }
                _ => {}
            }
            if !active {
                continue;
            }
            self.close_rule(&mut open);
            let eq = line.find('=');
            let col = find_col(&line);
            let is_assign = match eq {
                Some(e) => col.is_none() || col.unwrap() > e || (e > 0 && col.unwrap() == e - 1),
                None => false,
            };
            if is_assign {
                let e = eq.unwrap();
                let lb = line.as_bytes();
                let (op, nend) = if e > 0 && (lb[e - 1] == b':' || lb[e - 1] == b'?' || lb[e - 1] == b'+') {
                    (lb[e - 1] as char, e - 1)
                } else {
                    ('=', e)
                };
                let name = self.expand(&line[..nend])?;
                let name = name.trim_matches(|c| c == ' ' || c == '\t' || c == '\n').to_string();
                if name.is_empty() {
                    return Err(self.fatal("empty variable name"));
                }
                if self.cmdvars.contains(&name) {
                    continue;
                }
                let value = line[e + 1..].trim_matches(|c| c == ' ' || c == '\t').to_string();
                match op {
                    '=' => {
                        self.vars.insert(name, Var { value, simple: false });
                    }
                    ':' => {
                        let v = self.expand(&value)?;
                        self.vars.insert(name, Var { value: v, simple: true });
                    }
                    '?' => {
                        if !self.vars.contains_key(&name) {
                            self.vars.insert(name, Var { value, simple: false });
                        }
                    }
                    _ => match self.vars.get(&name).cloned() {
                        None => {
                            self.vars.insert(name, Var { value, simple: false });
                        }
                        Some(old) => {
                            let add = if old.simple { self.expand(&value)? } else { value };
                            let nv = if old.value.is_empty() || add.is_empty() {
                                format!("{}{}", old.value, add)
                            } else {
                                format!("{} {}", old.value, add)
                            };
                            self.vars.insert(name, Var { value: nv, simple: old.simple });
                        }
                    },
                }
                continue;
            }
            match col {
                None => {
                    let t = self.expand(&line)?;
                    if !t.trim().is_empty() {
                        return Err(self.fatal("missing separator"));
                    }
                }
                Some(c) => {
                    let tt = self.expand(&line[..c])?;
                    let after = &line[c + 1..];
                    let (pre, cmd) = match after.find(';') {
                        Some(s) => (&after[..s], Some(after[s + 1..].trim_start_matches(|c| c == ' ' || c == '\t').to_string())),
                        None => (after, None),
                    };
                    let pt = self.expand(pre)?;
                    let (np, op) = match pt.find('|') {
                        Some(p) => (&pt[..p], &pt[p + 1..]),
                        None => (&pt[..], ""),
                    };
                    let mut r = OpenRule {
                        line: lineno,
                        targets: words(&tt),
                        prereqs: words(np),
                        order: words(op),
                        recipe: Vec::new(),
                    };
                    if let Some(cmd) = cmd {
                        r.recipe.push((cmd, lineno));
                    }
                    open = Some(r);
                }
            }
        }
        // EOF
        self.close_rule(&mut open);
        if let Some(c) = conds.last() {
            self.cur_line = Some(c.line);
            return Err(self.fatal("missing 'endif'"));
        }
        self.cur_line = None;
        Ok(())
    }

    fn is_phony(&self, t: &str) -> bool {
        self.phony.iter().any(|p| p == t)
    }

    fn can_make(&self, name: &str, depth: usize) -> bool {
        self.files.contains_key(name)
            || self.explicit.contains_key(name)
            || self.is_phony(name)
            || (depth < 8 && self.find_pattern(name, depth + 1).is_some())
    }

    fn find_pattern(&self, t: &str, depth: usize) -> Option<(usize, String)> {
        for (idx, p) in self.patterns.iter().enumerate() {
            if p.recipe.is_empty() {
                continue;
            }
            let pp = match p.pat.find('%') {
                Some(x) => x,
                None => continue,
            };
            let pre = &p.pat[..pp];
            let suf = &p.pat[pp + 1..];
            if t.len() <= pre.len() + suf.len() || !t.starts_with(pre) || !t.ends_with(suf) {
                continue;
            }
            let stem = &t[pre.len()..t.len() - suf.len()];
            if p
                .prereqs
                .iter()
                .chain(p.order.iter())
                .all(|n| self.can_make(&subst_pct(n, stem), depth))
            {
                return Some((idx, stem.to_string()));
            }
        }
        None
    }

    fn resolve(&self, t: &str) -> Option<Resolved> {
        let ex = self.explicit.get(t);
        if let Some(e) = ex {
            if !e.recipe.is_empty() {
                return Some(Resolved {
                    prereqs: e.prereqs.clone(),
                    order: e.order.clone(),
                    recipe: e.recipe.clone(),
                    stem: String::new(),
                });
            }
        }
        if let Some((idx, stem)) = self.find_pattern(t, 0) {
            let p = &self.patterns[idx];
            let mut prereqs: Vec<String> = p.prereqs.iter().map(|n| subst_pct(n, &stem)).collect();
            let mut order: Vec<String> = p.order.iter().map(|n| subst_pct(n, &stem)).collect();
            if let Some(e) = ex {
                prereqs.extend(e.prereqs.iter().cloned());
                order.extend(e.order.iter().cloned());
            }
            return Some(Resolved { prereqs, order, recipe: p.recipe.clone(), stem });
        }
        ex.map(|e| Resolved {
            prereqs: e.prereqs.clone(),
            order: e.order.clone(),
            recipe: Vec::new(),
            stem: String::new(),
        })
    }

    fn tick(&mut self) -> i64 {
        self.clock += 1;
        self.clock
    }

    fn update(&mut self, t: &str, needed_by: Option<&str>) -> R<bool> {
        if let Some(&r) = self.memo.get(t) {
            return Ok(r);
        }
        if let Some(pos) = self.stack.iter().position(|x| x == t) {
            let mut path: Vec<String> = self.stack[pos..].to_vec();
            path.push(t.to_string());
            return Err(format!("make: *** Circular dependency detected: {}.  Stop.", path.join(" -> ")));
        }
        let res = match self.resolve(t) {
            None => {
                let r = if self.files.contains_key(t) {
                    false
                } else if self.is_phony(t) {
                    true
                } else {
                    return Err(match needed_by {
                        Some(n) => format!("make: *** No rule to make target '{}', needed by '{}'.  Stop.", t, n),
                        None => format!("make: *** No rule to make target '{}'.  Stop.", t),
                    });
                };
                self.memo.insert(t.to_string(), r);
                return Ok(r);
            }
            Some(r) => r,
        };
        let in_table = self.files.contains_key(t);
        let mt = self.files.get(t).copied().unwrap_or(0);
        self.stack.push(t.to_string());
        let prereqs = dedup(&res.prereqs);
        let mut changed = false;
        let mut newer = false;
        for p in &prereqs {
            if self.update(p, Some(t))? {
                changed = true;
            }
            if in_table {
                if let Some(&pm) = self.files.get(p) {
                    if pm > mt {
                        newer = true;
                    }
                }
            }
        }
        let order = dedup(&res.order);
        for p in &order {
            self.update(p, Some(t))?;
        }
        self.stack.pop();
        let phony = self.is_phony(t);
        let mut result = false;
        if phony || !self.files.contains_key(t) || changed || newer {
            result = true;
            if !res.recipe.is_empty() {
                let mut qm = Vec::new();
                for p in &prereqs {
                    if !in_table
                        || self.memo.get(p.as_str()).copied().unwrap_or(false)
                        || self.files.get(p).map(|&m| m > mt).unwrap_or(false)
                    {
                        qm.push(p.clone());
                    }
                }
                let auto = Auto {
                    target: t.to_string(),
                    first: res.prereqs.first().cloned().unwrap_or_default(),
                    all: prereqs.join(" "),
                    newer: qm.join(" "),
                    order: order.join(" "),
                    stem: res.stem.clone(),
                };
                self.auto = Some(auto);
                let r = self.run_recipe(t, &res.recipe, phony);
                self.auto = None;
                r?;
            }
        }
        self.memo.insert(t.to_string(), result);
        Ok(result)
    }

    fn run_recipe(&mut self, t: &str, recipe: &[(String, usize)], phony: bool) -> R<()> {
        self.recipes_run += 1;
        for (text, ln) in recipe {
            self.cur_line = Some(*ln);
            let r = self.expand(text);
            self.cur_line = None;
            let e = r?;
            let mut s = e.trim().to_string();
            let mut silent = false;
            let mut ignore = false;
            loop {
                s = s.trim_start().to_string();
                match s.chars().next() {
                    Some('@') => silent = true,
                    Some('-') => ignore = true,
                    Some('+') => {}
                    _ => break,
                }
                s.remove(0);
            }
            let cmd = s.trim().to_string();
            if cmd.is_empty() {
                continue;
            }
            if self.dry {
                self.out.push_str(&cmd);
                self.out.push('\n');
                continue;
            }
            if !silent {
                self.out.push_str(&cmd);
                self.out.push('\n');
            }
            let w = words(&cmd);
            let args = &w[1..];
            let mut status: i64 = 0;
            match w[0].as_str() {
                "false" => status = 1,
                "exit" => {
                    status = match args.first() {
                        None => 0,
                        Some(n) => n.parse::<i64>().unwrap_or(2),
                    }
                }
                "touch" => {
                    for a in args {
                        if !a.starts_with('-') {
                            let c = self.tick();
                            self.files.insert(a.clone(), c);
                        }
                    }
                }
                "rm" => {
                    for a in args {
                        if !a.starts_with('-') {
                            self.files.remove(a);
                        }
                    }
                }
                "cp" => {
                    if args.len() == 2 {
                        if !self.files.contains_key(&args[0]) {
                            self.out.push_str(&format!("cp: cannot stat '{}': No such file or directory\n", args[0]));
                            status = 1;
                        } else {
                            let c = self.tick();
                            self.files.insert(args[1].clone(), c);
                        }
                    }
                }
                "echo" => {
                    let a: Vec<String> = args.iter().map(|x| x.replace('\'', "").replace('"', "")).collect();
                    self.out.push_str(&a.join(" "));
                    self.out.push('\n');
                }
                _ => {}
            }
            if status != 0 {
                if ignore {
                    self.out.push_str(&format!("make: [Makefile:{}: {}] Error {} (ignored)\n", ln, t, status));
                } else {
                    self.out.push_str(&format!("make: *** [Makefile:{}: {}] Error {}\n", ln, t, status));
                    return Err(String::new());
                }
            }
        }
        if !self.dry && !phony {
            let c = self.tick();
            self.files.insert(t.to_string(), c);
        }
        Ok(())
    }

    fn emit(&mut self, e: String) {
        if !e.is_empty() {
            self.out.push_str(&e);
            self.out.push('\n');
        }
    }

    fn deps(&self, t: &str, visited: &mut HashSet<String>, stack: &mut Vec<String>, out: &mut Vec<String>) -> R<()> {
        let res = match self.resolve(t) {
            Some(r) => r,
            None => return Ok(()),
        };
        let mut all = dedup(&res.prereqs);
        all.extend(dedup(&res.order));
        for p in all {
            if let Some(pos) = stack.iter().position(|x| *x == p) {
                let mut path: Vec<String> = stack[pos..].to_vec();
                path.push(p.clone());
                return Err(format!("make: *** Circular dependency detected: {}.  Stop.", path.join(" -> ")));
            }
            if visited.contains(&p) {
                continue;
            }
            stack.push(p.clone());
            self.deps(&p, visited, stack, out)?;
            stack.pop();
            visited.insert(p.clone());
            out.push(p);
        }
        Ok(())
    }

    fn request(&mut self, mk: &str, line: &str) {
        let line_t = line.trim_end();
        self.out.push_str(&format!("> {}\n", line_t));
        let ws: Vec<&str> = line_t.split_whitespace().collect();
        let cmd = ws[0];
        let args = &ws[1..];
        self.expanding.clear();
        self.foreach.clear();
        self.auto = None;
        self.cur_line = None;
        match cmd {
            "files" => {
                if self.files.is_empty() {
                    self.out.push_str("(no files)\n");
                }
                let s: Vec<String> = self.files.iter().map(|(k, v)| format!("{} {}\n", k, v)).collect();
                for x in s {
                    self.out.push_str(&x);
                }
            }
            "touch" => {
                if args.len() == 1 {
                    let c = self.tick();
                    self.files.insert(args[0].to_string(), c);
                } else if args.len() == 2 {
                    match args[1].parse::<i64>() {
                        Ok(n) => {
                            self.files.insert(args[0].to_string(), n);
                            if n > self.clock {
                                self.clock = n;
                            }
                        }
                        Err(_) => self.out.push_str("bad request\n"),
                    }
                } else {
                    self.out.push_str("bad request\n");
                }
            }
            "rm" => {
                for a in args {
                    self.files.remove(*a);
                }
            }
            "expand" => {
                self.reset_parse();
                if let Err(e) = self.parse(mk) {
                    self.emit(e);
                    return;
                }
                let text = line_t.trim_start()[6..].trim().to_string();
                match self.expand(&text) {
                    Ok(r) => self.out.push_str(&format!("[{}]\n", r)),
                    Err(e) => self.emit(e),
                }
            }
            "build" | "dry" | "deps" | "targets" => {
                self.reset_parse();
                let mut cv: Vec<(String, String)> = Vec::new();
                let mut goals: Vec<String> = Vec::new();
                for a in args {
                    match a.find('=') {
                        Some(p) if p > 0 => cv.push((a[..p].to_string(), a[p + 1..].to_string())),
                        _ => goals.push(a.to_string()),
                    }
                }
                for (k, v) in cv {
                    self.vars.insert(k.clone(), Var { value: v, simple: false });
                    self.cmdvars.insert(k);
                }
                if let Err(e) = self.parse(mk) {
                    self.emit(e);
                    return;
                }
                match cmd {
                    "targets" => {
                        if let Some(d) = &self.default {
                            self.out.push_str(&format!("default: {}\n", d));
                        }
                        let fmt = |n: &str, p: &Vec<String>, o: &Vec<String>| {
                            let mut s = format!("{}:", n);
                            if !p.is_empty() {
                                s.push(' ');
                                s.push_str(&p.join(" "));
                            }
                            if !o.is_empty() {
                                s.push_str(" | ");
                                s.push_str(&o.join(" "));
                            }
                            s.push('\n');
                            s
                        };
                        let mut s = String::new();
                        for t in &self.order {
                            let e = &self.explicit[t];
                            s.push_str(&fmt(t, &e.prereqs, &e.order));
                        }
                        for p in &self.patterns {
                            s.push_str(&fmt(&format!("pattern {}", p.pat), &p.prereqs, &p.order));
                        }
                        if !self.phony.is_empty() {
                            s.push_str(&format!("phony: {}\n", self.phony.join(" ")));
                        }
                        self.out.push_str(&s);
                    }
                    "deps" => {
                        if goals.len() != 1 {
                            self.out.push_str("usage: deps TARGET\n");
                            return;
                        }
                        let mut out = Vec::new();
                        let mut visited = HashSet::new();
                        let mut stack = vec![goals[0].clone()];
                        match self.deps(&goals[0], &mut visited, &mut stack, &mut out) {
                            Err(e) => self.emit(e),
                            Ok(()) => {
                                if out.is_empty() {
                                    self.out.push_str("(no prerequisites)\n");
                                }
                                for o in out {
                                    self.out.push_str(&o);
                                    self.out.push('\n');
                                }
                            }
                        }
                    }
                    _ => {
                        self.dry = cmd == "dry";
                        if goals.is_empty() {
                            match &self.default {
                                Some(d) => goals.push(d.clone()),
                                None => {
                                    self.out.push_str("make: *** No targets.  Stop.\n");
                                    return;
                                }
                            }
                        }
                        for g in goals {
                            let before = self.recipes_run;
                            if let Err(e) = self.update(&g, None) {
                                self.emit(e);
                                return;
                            }
                            if self.recipes_run == before {
                                let has_recipe = self.resolve(&g).map(|r| !r.recipe.is_empty()).unwrap_or(false);
                                if has_recipe || (!self.is_phony(&g) && self.files.contains_key(&g)) {
                                    self.out.push_str(&format!("make: '{}' is up to date.\n", g));
                                } else {
                                    self.out.push_str(&format!("make: Nothing to be done for '{}'.\n", g));
                                }
                            }
                        }
                        self.dry = false;
                    }
                }
            }
            _ => self.out.push_str(&format!("unknown request: {}\n", cmd)),
        }
    }
}

fn split_args_raw(s: &str) -> Vec<String> {
    let mut v = Vec::new();
    let mut d = 0i32;
    let mut cur = String::new();
    for ch in s.chars() {
        match ch {
            '(' | '{' => {
                d += 1;
                cur.push(ch)
            }
            ')' | '}' => {
                if d > 0 {
                    d -= 1;
                }
                cur.push(ch)
            }
            ',' if d == 0 => {
                v.push(cur.clone());
                cur.clear();
            }
            _ => cur.push(ch),
        }
    }
    v.push(cur);
    v
}

fn real_main() {
    let mut buf = Vec::new();
    std::io::stdin().read_to_end(&mut buf).unwrap();
    let text = String::from_utf8_lossy(&buf).to_string();
    let lines: Vec<&str> = text.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
    let mut sec = 0;
    let mut mk: Vec<&str> = Vec::new();
    let mut tab: Vec<&str> = Vec::new();
    let mut reqs: Vec<&str> = Vec::new();
    for l in &lines {
        if sec < 2 && *l == "====" {
            sec += 1;
            continue;
        }
        match sec {
            0 => mk.push(l),
            1 => tab.push(l),
            _ => reqs.push(l),
        }
    }
    let mkt = mk.join("\n");
    let mut m = M::default();
    for l in tab {
        let f: Vec<&str> = l.split_whitespace().collect();
        if f.len() == 2 {
            if let Ok(n) = f[1].parse::<i64>() {
                if n >= 0 {
                    m.files.insert(f[0].to_string(), n);
                    if n > m.clock {
                        m.clock = n;
                    }
                }
            }
        }
    }
    for r in reqs {
        let t = r.trim_start();
        if t.trim().is_empty() || t.starts_with('#') {
            continue;
        }
        m.request(&mkt, r);
    }
    std::io::stdout().write_all(m.out.as_bytes()).unwrap();
}

fn main() {
    std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(real_main)
        .unwrap()
        .join()
        .unwrap();
}
