//! Temporary oracle for compiler/src/effects.c: crates/ms-check/src/effect_directives.rs, copied
//! verbatim, behind a line protocol. Deleted with the Rust checker.
//!   effects_oracle gen COUNT SEED   prints COUNT random cases
//!   effects_oracle                  answers the cases on stdin, one line each
//! Cases (tab-separated; `\n` and `\r` in a source stand for the characters):
//!   M pattern effect | H source | A line source
use std::io::{BufRead, Write};

// ---- copied from crates/ms-check/src/effect_directives.rs ----

/// The directive lines found in one comment block.
#[derive(Default, Clone, Debug, PartialEq, Eq)]
pub struct Directives {
    /// `// ms: effect NAME`: effects the function declares.
    pub declared: Vec<String>,
    /// `// ms: allow_effect PATTERN`: permissions; `None` when no line was written, so an
    /// absent scope is distinct from an empty one.
    pub allow: Option<Vec<String>>,
}

impl Directives {
    fn line(&mut self, text: &str) {
        let Some(rest) = text.trim().strip_prefix("// ms:") else {
            return;
        };
        let rest = rest.trim();
        if let Some(name) = rest.strip_prefix("allow_effect ") {
            self.allow
                .get_or_insert_with(Vec::new)
                .push(name.trim().to_string());
        } else if let Some(name) = rest.strip_prefix("effect ") {
            self.declared.push(name.trim().to_string());
        }
    }
}

/// The comment lines of a source file, for header and per-declaration lookups.
pub struct Lines<'a> {
    lines: Vec<&'a str>,
}

impl<'a> Lines<'a> {
    /// Indexes the lines of `source` (CR stripped).
    pub fn new(source: &'a str) -> Lines<'a> {
        Lines {
            lines: source
                .split('\n')
                .map(|l| l.trim_end_matches('\r'))
                .collect(),
        }
    }

    /// The file header: `//` lines at the top of the file, ended by a blank line. A comment block
    /// that runs straight into code belongs to that declaration, not to the file.
    pub fn header(&self) -> Directives {
        let mut found = Directives::default();
        let comments = self
            .lines
            .iter()
            .take_while(|l| l.trim_start().starts_with("//"))
            .count();
        if comments == 0
            || self
                .lines
                .get(comments)
                .is_none_or(|l| !l.trim().is_empty())
        {
            return found;
        }
        for line in &self.lines[..comments] {
            found.line(line);
        }
        found
    }

    /// The `//` lines directly above the 1-based `line`, up to a blank or code line.
    pub fn above(&self, line: u32) -> Directives {
        let mut found = Directives::default();
        let mut at = (line as usize).saturating_sub(1);
        while at > 0 && self.lines[at - 1].trim_start().starts_with("//") {
            found.line(self.lines[at - 1]);
            at -= 1;
        }
        found
    }
}

/// Whether `effect` matches `pattern`: `*` matches everything, `a.b.*` a prefix, `*.write` a last
/// segment, and any other pattern only itself.
pub fn matches(pattern: &str, effect: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    if let Some(prefix) = pattern.strip_suffix(".*") {
        return effect
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with('.'));
    }
    if let Some(suffix) = pattern.strip_prefix("*.") {
        return effect
            .rsplit_once('.')
            .is_some_and(|(_, last)| last == suffix);
    }
    pattern == effect
}


// ---- protocol ----

fn unescape(s: &str) -> String {
    s.replace("\\n", "\n").replace("\\r", "\r")
}

fn show(d: &Directives) -> String {
    let allow = match &d.allow {
        None => "-".to_string(),
        Some(a) => format!("<{}>", a.join(";")),
    };
    format!("allow={allow} declared=<{}>", d.declared.join(";"))
}

fn answer(line: &str) -> String {
    let f: Vec<&str> = line.split('\t').collect();
    match f[0] {
        "M" => matches(f[1], f[2]).to_string(),
        "H" => show(&Lines::new(&unescape(f[1])).header()),
        "A" => show(&Lines::new(&unescape(f[2])).above(f[1].parse().unwrap())),
        other => panic!("unknown op {other}"),
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const SEGMENTS: &[&str] = &["std", "fs", "read", "write", "db", "net", "connect", "*", "", "x"];
const LINES: &[&str] = &[
    "// ms: effect db.write",
    "// ms: allow_effect std.fs.read",
    "// ms: allow_effect  *.write ",
    "//ms: effect x",
    "  // ms: effect  std.net.connect  ",
    "// ms: allow_effect",
    "// ms: effect",
    "// ms:effect y",
    "// ms: allow_effect std.*",
    "// notes",
    "//",
    "",
    "   ",
    "fn a() Void:",
    "export fn exec() Void:",
    "    return",
];

fn dotted(r: &mut Rng) -> String {
    let n = 1 + r.below(3);
    (0..n).map(|_| SEGMENTS[r.below(SEGMENTS.len())]).collect::<Vec<_>>().join(".")
}

fn source(r: &mut Rng) -> String {
    let n = r.below(8);
    let sep = if r.below(4) == 0 { "\\r\\n" } else { "\\n" };
    (0..n).map(|_| LINES[r.below(LINES.len())]).collect::<Vec<_>>().join(sep)
}

fn gen(count: usize, seed: u64) {
    let mut r = Rng(seed.max(1));
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let line = match r.below(3) {
            0 => format!("M\t{}\t{}", dotted(&mut r), dotted(&mut r)),
            1 => format!("H\t{}", source(&mut r)),
            _ => {
                let s = source(&mut r);
                let lines = s.matches("\\n").count() + 1;
                format!("A\t{}\t{s}", 1 + r.below(lines + 1))
            }
        };
        writeln!(out, "{line}").unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("gen") {
        gen(args[2].parse().unwrap(), args[3].parse().unwrap());
        return;
    }
    let stdin = std::io::stdin();
    let out = std::io::stdout();
    let mut out = out.lock();
    for line in stdin.lock().lines() {
        writeln!(out, "{}", answer(&line.unwrap())).unwrap();
    }
}
