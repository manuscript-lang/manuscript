//! Deterministic generators of small Manuscript programs for differential testing.
//!
//! * `program(seed)`: a well-typed program over Int, Float, Bool, String and
//!   `List[Int]` expression trees, loops and a few recursive helpers. Checked Int
//!   arithmetic is tracked while generating so most programs finish; roughly one
//!   in five ends in a deliberate fault (overflow, division by zero, index out of
//!   range) after printing its earlier results.
//! * `type_error(seed)`: the same kind of program with one injected type error.
//! * `syntax_error(seed)`: the same kind of program with one text mutation.
//!
//! The output of every generated program is recorded from the oracle, so the
//! generators only have to produce programs the oracle accepts or rejects the
//! same way every time.

/// SplitMix64: tiny, fast and reproducible across platforms.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ 0xD1B5_4A32_D192_ED03)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    pub fn below(&mut self, n: u64) -> u64 {
        self.next_u64() % n.max(1)
    }

    pub fn range(&mut self, lo: i64, hi: i64) -> i64 {
        lo + self.below((hi - lo + 1) as u64) as i64
    }

    pub fn chance(&mut self, percent: u64) -> bool {
        self.below(100) < percent
    }

    pub fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[self.below(items.len() as u64) as usize]
    }
}

/// A generated program and the feature tags it exercises.
pub struct Generated {
    pub source: String,
    pub tags: Vec<&'static str>,
}

const WORDS: &[&str] = &[
    "alpha",
    "beta",
    "gamma",
    "delta",
    "ms",
    "x",
    "hello world",
    "  padded  ",
    "Tab\\there",
    "line\\nbreak",
    "quote\\\"d",
    "back\\\\slash",
    "brace\\{s\\}",
    "héllo",
    "日本語",
    "naïve",
    "emoji 😀",
    "",
    "a",
    "MiXeD CaSe",
    "42",
];

#[derive(Clone)]
struct IntVar {
    name: String,
    value: i64,
}

#[derive(Clone)]
struct StrVar {
    name: String,
    chars: Option<usize>,
}

#[derive(Clone)]
struct ListVar {
    name: String,
    items: Vec<i64>,
}

struct Gen {
    rng: Rng,
    ints: Vec<IntVar>,
    floats: Vec<String>,
    bools: Vec<String>,
    strs: Vec<StrVar>,
    lists: Vec<ListVar>,
    next_id: usize,
    out: Vec<String>,
    helpers: Vec<String>,
    tags: Vec<&'static str>,
    uses_range: bool,
    /// Line counts of `out` at statement boundaries (safe places to splice).
    bounds: Vec<usize>,
}

fn int_literal(rng: &mut Rng) -> i64 {
    match rng.below(100) {
        0..=69 => rng.range(-50, 50),
        70..=89 => rng.range(-1_000_000, 1_000_000),
        90..=97 => rng.range(-1_000_000_000_000, 1_000_000_000_000),
        _ => *rng.pick(&[i64::MAX, i64::MIN, i64::MAX - 1, i64::MIN + 1, 0, 1, -1]),
    }
}

/// Source text of an Int literal; negatives are parenthesized so they nest anywhere.
fn int_code(n: i64) -> String {
    if n == i64::MIN {
        "(-9223372036854775808)".to_string()
    } else if n < 0 {
        format!("({n})")
    } else {
        n.to_string()
    }
}

fn float_literal(rng: &mut Rng) -> String {
    match rng.below(10) {
        0 => "0.0".to_string(),
        1 => format!("{}.5", rng.range(0, 9)),
        2 => format!("{}.25", rng.range(0, 1000)),
        3 => format!("{}.0e{}", rng.range(1, 9), rng.range(-9, 25)),
        _ => {
            let whole = rng.range(0, 999);
            let frac = rng.range(0, 999);
            format!("{whole}.{frac:03}")
        }
    }
}

impl Gen {
    fn id(&mut self, prefix: &str) -> String {
        self.next_id += 1;
        format!("{prefix}{}", self.next_id)
    }

    /// An Int expression and its value, or `None` for the value when evaluation faults.
    fn int_expr(&mut self, depth: u32) -> (String, Option<i64>) {
        if depth == 0 || self.rng.chance(25) {
            return self.int_leaf();
        }
        match self.rng.below(12) {
            0..=2 => {
                let (a, av) = self.int_expr(depth - 1);
                let (b, bv) = self.int_expr(depth - 1);
                let v = av.zip(bv).and_then(|(x, y)| x.checked_add(y));
                (format!("({a} + {b})"), v)
            }
            3 | 4 => {
                let (a, av) = self.int_expr(depth - 1);
                let (b, bv) = self.int_expr(depth - 1);
                let v = av.zip(bv).and_then(|(x, y)| x.checked_sub(y));
                (format!("({a} - {b})"), v)
            }
            5 | 6 => {
                let (a, av) = self.int_expr(depth - 1);
                let (b, bv) = self.int_expr(depth - 1);
                let v = av.zip(bv).and_then(|(x, y)| x.checked_mul(y));
                (format!("({a} * {b})"), v)
            }
            7 => {
                let (a, av) = self.int_expr(depth - 1);
                let (b, bv) = self.int_expr(depth - 1);
                let v = av.zip(bv).and_then(|(x, y)| x.checked_div(y));
                (format!("({a} / {b})"), v)
            }
            8 => {
                let (a, av) = self.int_expr(depth - 1);
                let (b, bv) = self.int_expr(depth - 1);
                let v = av.zip(bv).and_then(|(x, y)| x.checked_rem(y));
                (format!("({a} % {b})"), v)
            }
            9 => {
                let (a, av) = self.int_expr(depth - 1);
                (format!("(-{a})"), av.and_then(i64::checked_neg))
            }
            10 => {
                if let Some(s) = self.pick_str() {
                    let v = s.chars.map(|n| n as i64);
                    self.tags.push("strings");
                    (format!("{}.length()", s.name), v)
                } else {
                    self.int_leaf()
                }
            }
            _ => {
                if self.lists.is_empty() {
                    return self.int_leaf();
                }
                let l = self.rng.pick(&self.lists).clone();
                self.tags.push("lists");
                if self.rng.chance(50) || l.items.is_empty() {
                    (format!("{}.length()", l.name), Some(l.items.len() as i64))
                } else {
                    let i = self.rng.below(l.items.len() as u64) as usize;
                    (format!("{}.get({i})", l.name), Some(l.items[i]))
                }
            }
        }
    }

    fn pick_str(&mut self) -> Option<StrVar> {
        if self.strs.is_empty() {
            None
        } else {
            Some(self.rng.pick(&self.strs).clone())
        }
    }

    fn int_leaf(&mut self) -> (String, Option<i64>) {
        if !self.ints.is_empty() && self.rng.chance(55) {
            let v = self.rng.pick(&self.ints).clone();
            return (v.name, Some(v.value));
        }
        let n = int_literal(&mut self.rng);
        (int_code(n), Some(n))
    }

    /// Retry until the expression does not fault.
    fn safe_int(&mut self, depth: u32) -> (String, i64) {
        for _ in 0..24 {
            let (code, v) = self.int_expr(depth);
            if let Some(v) = v {
                return (code, v);
            }
        }
        let n = self.rng.range(-20, 20);
        (int_code(n), n)
    }

    fn float_expr(&mut self, depth: u32) -> String {
        if depth == 0 || self.rng.chance(30) {
            if !self.floats.is_empty() && self.rng.chance(50) {
                return self.rng.pick(&self.floats).clone();
            }
            let lit = float_literal(&mut self.rng);
            return lit;
        }
        let a = self.float_expr(depth - 1);
        let b = self.float_expr(depth - 1);
        match self.rng.below(6) {
            0 | 1 => format!("({a} + {b})"),
            2 => format!("({a} - {b})"),
            3 | 4 => format!("({a} * {b})"),
            _ => format!("({a} / {b})"),
        }
    }

    fn str_expr(&mut self, depth: u32) -> (String, Option<usize>) {
        if depth == 0 || self.rng.chance(35) {
            if !self.strs.is_empty() && self.rng.chance(45) {
                let v = self.rng.pick(&self.strs).clone();
                return (v.name, v.chars);
            }
            let w = *self.rng.pick(WORDS);
            return (format!("f\"{w}\""), Some(escaped_len(w)));
        }
        let (a, al) = self.str_expr(depth - 1);
        match self.rng.below(9) {
            0..=2 => {
                let (b, bl) = self.str_expr(depth - 1);
                (format!("({a} + {b})"), al.zip(bl).map(|(x, y)| x + y))
            }
            3 => (format!("{a}.upper()"), al),
            4 => (format!("{a}.lower()"), al),
            5 => (format!("{a}.trim()"), None),
            6 => (format!("{a}.reverse()"), al),
            7 => {
                let (n, nv) = self.safe_int(1);
                let _ = nv;
                (format!("(\"{{{n}}}:\" + {a})"), None)
            }
            _ => {
                let (b, _) = self.str_expr(0);
                let (c, _) = self.str_expr(0);
                (format!("{a}.replace({b}, {c})"), None)
            }
        }
    }

    fn bool_expr(&mut self, depth: u32) -> String {
        if depth == 0 || self.rng.chance(20) {
            if !self.bools.is_empty() && self.rng.chance(50) {
                return self.rng.pick(&self.bools).clone();
            }
            return if self.rng.chance(50) { "true" } else { "false" }.to_string();
        }
        match self.rng.below(9) {
            0 => {
                let (a, _) = self.safe_int(depth - 1);
                let (b, _) = self.safe_int(depth - 1);
                let op = *self.rng.pick(&["<", "<=", ">", ">=", "==", "!="]);
                format!("({a} {op} {b})")
            }
            1 => {
                let a = self.float_expr(depth - 1);
                let b = self.float_expr(depth - 1);
                let op = *self.rng.pick(&["<", ">", "==", "!="]);
                format!("({a} {op} {b})")
            }
            2 => {
                let (a, _) = self.str_expr(depth - 1);
                let (b, _) = self.str_expr(0);
                let m = *self.rng.pick(&["contains", "starts_with", "ends_with"]);
                format!("{a}.{m}({b})")
            }
            3 => {
                let (a, _) = self.str_expr(depth - 1);
                let (b, _) = self.str_expr(depth - 1);
                let op = *self.rng.pick(&["==", "!="]);
                format!("({a} {op} {b})")
            }
            4 => format!("(not {})", self.bool_expr(depth - 1)),
            5 | 6 => format!(
                "({} and {})",
                self.bool_expr(depth - 1),
                self.bool_expr(depth - 1)
            ),
            7 => format!(
                "({} or {})",
                self.bool_expr(depth - 1),
                self.bool_expr(depth - 1)
            ),
            _ => {
                let (a, _) = self.str_expr(depth - 1);
                format!("{a}.is_empty()")
            }
        }
    }

    /// A small bounded list expression with a tracked value.
    fn list_expr(&mut self, depth: u32) -> (String, Vec<i64>) {
        if depth == 0 || self.lists.is_empty() || self.rng.chance(30) {
            let n = self.rng.below(6) as usize;
            let items: Vec<i64> = (0..n).map(|_| self.rng.range(-30, 30)).collect();
            let code = format!(
                "[{}]",
                items
                    .iter()
                    .map(|n| int_code(*n))
                    .collect::<Vec<_>>()
                    .join(", ")
            );
            if items.is_empty() {
                // An empty literal has no element type; spell one out.
                return ("[1, 2, 3].take(0)".to_string(), items);
            }
            return (code, items);
        }
        let base = self.rng.pick(&self.lists).clone();
        self.tags.push("closures");
        match self.rng.below(9) {
            0 => {
                let k = self.rng.range(2, 9);
                (
                    format!("{}.map(fn(x): x * {k})", base.name),
                    base.items.iter().map(|x| x * k).collect(),
                )
            }
            1 => {
                let k = self.rng.range(-5, 5);
                (
                    format!("{}.filter(lambda x: x > {})", base.name, int_code(k)),
                    base.items.iter().copied().filter(|x| *x > k).collect(),
                )
            }
            2 => {
                let mut v = base.items.clone();
                v.sort();
                (format!("{}.sorted(lambda a, b: a.compare(b))", base.name), v)
            }
            3 => {
                let mut v = base.items.clone();
                v.reverse();
                (format!("{}.reversed()", base.name), v)
            }
            4 => {
                let other = self.rng.pick(&self.lists).clone();
                let mut v = base.items.clone();
                v.extend(other.items.iter());
                (format!("{}.concat({})", base.name, other.name), v)
            }
            5 => {
                let n = self.rng.range(0, 4);
                (
                    format!("{}.take({n})", base.name),
                    base.items.iter().take(n as usize).copied().collect(),
                )
            }
            6 => {
                let n = self.rng.range(0, 4);
                (
                    format!("{}.drop({n})", base.name),
                    base.items.iter().skip(n as usize).copied().collect(),
                )
            }
            7 => {
                // append mutates its receiver and returns it; clone first.
                let k = self.rng.range(-9, 99);
                let mut v = base.items.clone();
                v.push(k);
                (format!("{}.clone().append({})", base.name, int_code(k)), v)
            }
            _ => {
                let k = self.rng.range(1, 4);
                (
                    format!(
                        "{}.map(fn(x): x + {k}).filter(fn(x): x % 2 == 0)",
                        base.name
                    ),
                    base.items
                        .iter()
                        .map(|x| x + k)
                        .filter(|x| x % 2 == 0)
                        .collect(),
                )
            }
        }
    }

    fn statement(&mut self) {
        self.statement_body();
        self.bounds.push(self.out.len());
    }

    fn statement_body(&mut self) {
        match self.rng.below(16) {
            0..=3 => {
                let (code, v) = self.safe_int(3);
                let name = self.id("i");
                self.out.push(format!("    let {name} = {code}"));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
                self.ints.push(IntVar { name, value: v });
                self.tags.push("numbers");
            }
            4 | 5 => {
                let code = self.float_expr(3);
                let name = self.id("f");
                self.out.push(format!("    let {name} = {code}"));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
                self.floats.push(name);
                self.tags.push("numbers");
            }
            6 | 7 => {
                let (code, len) = self.str_expr(3);
                let name = self.id("s");
                self.out.push(format!("    let {name} = {code}"));
                self.out.push(format!("    say(\"{name} = [{{{name}}}]\")"));
                self.strs.push(StrVar { name, chars: len });
                self.tags.push("strings");
                self.tags.push("interpolation");
            }
            8 | 9 => {
                let code = self.bool_expr(3);
                let name = self.id("b");
                self.out.push(format!("    let {name} = {code}"));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
                self.bools.push(name);
            }
            10 | 11 => {
                let (code, items) = self.list_expr(2);
                let name = self.id("l");
                self.out.push(format!("    let {name} = {code}"));
                self.out.push(format!(
                    "    say(\"{name} = {{{name}}} len {{{name}.length()}}\")"
                ));
                self.lists.push(ListVar { name, items });
                self.tags.push("lists");
            }
            12 => self.loop_statement(),
            13 => self.branch_statement(),
            14 => self.helper_call(),
            _ => {
                let (a, _) = self.safe_int(2);
                let (b, _) = self.safe_int(2);
                self.out.push(format!(
                    "    say(\"{{{a}}} {{{b}}} {{({a} < {b})}} sum {{{a} + {b}}}\")"
                ));
                self.tags.push("interpolation");
            }
        }
    }

    fn loop_statement(&mut self) {
        let n = self.rng.range(0, 8);
        let k = self.rng.range(-5, 9);
        let name = self.id("acc");
        let kind = self.rng.below(3);
        self.tags.push("control-flow");
        match kind {
            0 => {
                self.uses_range = true;
                self.out.push(format!("    var {name} = 0"));
                self.out.push(format!("    for i in range(0, {n}):"));
                self.out
                    .push(format!("        {name} += i * {}", int_code(k)));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
            }
            1 => {
                self.out.push(format!("    var {name} = 0"));
                self.out.push(format!("    var step{name} = 0"));
                self.out.push(format!("    while step{name} < {n}:"));
                self.out.push(format!("        step{name} += 1"));
                self.out.push(format!(
                    "        {name} += step{name} * step{name} + {}",
                    int_code(k)
                ));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
            }
            _ => {
                if self.lists.is_empty() {
                    return;
                }
                let l = self.rng.pick(&self.lists).clone();
                let total: i64 = l.items.iter().sum();
                self.out.push(format!("    var {name} = 0"));
                self.out.push(format!("    for x in {}:", l.name));
                self.out.push("        if x % 2 == 0:".to_string());
                self.out.push(format!("            {name} += x"));
                self.out.push("        else:".to_string());
                self.out.push(format!("            {name} -= 1"));
                self.out.push(format!("    say(\"{name} = {{{name}}}\")"));
                let _ = total;
            }
        }
    }

    fn branch_statement(&mut self) {
        let cond = self.bool_expr(2);
        let (a, _) = self.str_expr(1);
        let (b, _) = self.str_expr(1);
        self.tags.push("control-flow");
        self.out.push(format!("    if {cond}:"));
        self.out.push(format!("        say({a})"));
        self.out.push("    else:".to_string());
        self.out.push(format!("        say({b})"));
    }

    fn helper_call(&mut self) {
        self.tags.push("functions");
        match self.rng.below(4) {
            0 => {
                let n = self.rng.range(0, 20);
                self.helpers.push(HELPER_FACT.to_string());
                self.out
                    .push(format!("    say(\"fact({n}) = {{fact({n})}}\")"));
            }
            1 => {
                let n = self.rng.range(0, 60);
                self.helpers.push(HELPER_FIB.to_string());
                self.out
                    .push(format!("    say(\"fib({n}) = {{fib({n})}}\")"));
            }
            2 => {
                let (a, b) = (self.rng.range(1, 5000), self.rng.range(1, 5000));
                self.helpers.push(HELPER_GCD.to_string());
                self.out
                    .push(format!("    say(\"gcd({a}, {b}) = {{gcd({a}, {b})}}\")"));
            }
            _ => {
                let n = self.rng.range(1, 3000);
                self.helpers.push(HELPER_COLLATZ.to_string());
                self.out
                    .push(format!("    say(\"collatz({n}) = {{collatz({n})}}\")"));
            }
        }
    }

    /// A last statement that must fault, after everything above has printed.
    fn fault_statement(&mut self) {
        self.tags.push("faults");
        let big = self.id("big");
        let kind = self.rng.below(7);
        let k = self.rng.range(1, 5);
        let lines: Vec<String> = match kind {
            0 => vec![
                format!("    let {big} = 9223372036854775807"),
                format!("    say(\"{{{big} + {k}}}\")"),
            ],
            1 => vec![
                format!("    let {big} = 9223372036854775807"),
                format!("    say(\"{{{big} * {}}}\")", k + 1),
            ],
            2 => vec![
                format!("    let {big} = -9223372036854775808"),
                format!("    say(\"{{{big} - {k}}}\")"),
            ],
            3 => vec![
                format!("    let {big} = -9223372036854775808"),
                format!("    say(\"{{-{big}}}\")"),
            ],
            4 => {
                let (a, _) = self.safe_int(2);
                vec![
                    format!("    let {big} = {a} - {a}"),
                    format!("    say(\"{{{a} / {big}}}\")"),
                ]
            }
            5 => {
                let (a, _) = self.safe_int(2);
                vec![
                    format!("    let {big} = {a} - {a}"),
                    format!("    say(\"{{{a} % {big}}}\")"),
                ]
            }
            _ => {
                if self.lists.is_empty() {
                    vec![
                        format!("    let {big} = [1, 2, 3]"),
                        format!("    say(\"{{{big}.get({})}}\")", 3 + k),
                    ]
                } else {
                    let l = self.rng.pick(&self.lists).clone();
                    vec![format!(
                        "    say(\"{{{}.get({})}}\")",
                        l.name,
                        l.items.len() as i64 + k
                    )]
                }
            }
        };
        self.out.extend(lines);
    }
}

fn escaped_len(w: &str) -> usize {
    // Count the characters of the string after escape processing.
    let mut n = 0;
    let mut chars = w.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            chars.next();
        }
        n += 1;
    }
    n
}

const HELPER_FACT: &str =
    "def fact(n: Int) -> Int:\n    if n <= 1:\n        return 1\n    return n * fact(n - 1)\n";
const HELPER_FIB: &str = "def fib(n: Int) -> Int:\n    var a = 0\n    var b = 1\n    var i = 0\n    while i < n:\n        let next = a + b\n        a = b\n        b = next\n        i += 1\n    return a\n";
const HELPER_GCD: &str =
    "def gcd(a: Int, b: Int) -> Int:\n    if b == 0:\n        return a\n    return gcd(b, a % b)\n";
const HELPER_COLLATZ: &str = "def collatz(start: Int) -> Int:\n    var n = start\n    var steps = 0\n    while n != 1:\n        if n % 2 == 0:\n            n = n / 2\n        else:\n            n = 3 * n + 1\n        steps += 1\n    return steps\n";

fn assemble(g: Gen, seed: u64) -> Generated {
    let mut source = String::new();
    source.push_str(&format!("# Generated by ms-conform fuzz, seed {seed}.\n"));
    source.push_str("from \"@std/io.ms\" import stdout\n");
    if g.uses_range {
        source.push_str("from \"@std/collections.ms\" import range\n");
    }
    source.push_str(
        "\ndef say(text: String) -> Unit:\n    let written = stdout().write(f\"{text}\\n\")\n\n",
    );
    let mut seen = Vec::new();
    for h in &g.helpers {
        if !seen.contains(h) {
            source.push_str(h);
            source.push('\n');
            seen.push(h.clone());
        }
    }
    source.push_str("export def main() -> Int: ...\n");
    for line in &g.out {
        source.push_str(line);
        source.push('\n');
    }
    source.push_str("    return 0\n");
    let mut tags = g.tags;
    tags.sort_unstable();
    tags.dedup();
    Generated { source, tags }
}

fn new_gen(seed: u64) -> Gen {
    Gen {
        rng: Rng::new(seed),
        ints: Vec::new(),
        floats: Vec::new(),
        bools: Vec::new(),
        strs: Vec::new(),
        lists: Vec::new(),
        next_id: 0,
        out: Vec::new(),
        helpers: Vec::new(),
        tags: vec!["fuzz"],
        uses_range: false,
        bounds: Vec::new(),
    }
}

/// A valid program for `seed`.
pub fn program(seed: u64) -> Generated {
    let mut g = new_gen(seed);
    let count = 6 + g.rng.below(14);
    for _ in 0..count {
        g.statement();
    }
    if g.rng.chance(20) {
        g.fault_statement();
    }
    assemble(g, seed)
}

/// Statements that are each rejected by the checker, to splice into a valid program.
const TYPE_ERRORS: &[&str] = &[
    "    let bad: Int = \"text\"",
    "    let bad = 1 + \"one\"",
    "    let bad = undefined_name + 1",
    "    let bad = missing_function(3)",
    "    let bad: String = 5",
    "    let bad = [1, \"two\"]",
    "    let bad = 1.5 + 2",
    "    let bad = true + 1",
    "    let bad = say(1, 2)",
    "    let bad = \"abc\".no_such_method()",
    "    let fixed = 1\n    fixed = 2",
    "    let bad = (1 < 2) < 3",
    "    let bad: Bool = 1",
    "    let bad = not 5",
    "    let bad = [1, 2].get(\"x\")",
    "    let bad = 1 and 2",
    "    if 1:\n        say(\"truthy\")",
    "    let bad = say",
    "    return \"not an int\"",
    "    let bad = Map[Int, Int]().get(1, 2, 3)",
];

/// A program with one injected type error; checking it must fail the same way every time.
pub fn type_error(seed: u64) -> Generated {
    let mut g = new_gen(seed ^ 0x5eed);
    let count = 2 + g.rng.below(6);
    for _ in 0..count {
        g.statement();
    }
    let at = if g.bounds.is_empty() {
        0
    } else {
        let i = g.rng.below(g.bounds.len() as u64) as usize;
        g.bounds[i]
    };
    let error = *g.rng.pick(TYPE_ERRORS);
    g.out.insert(at, error.to_string());
    g.tags.push("diagnostics");
    g.tags.push("types");
    assemble(g, seed)
}

/// A valid program mutated at the text level; the oracle decides how it fails.
pub fn syntax_error(seed: u64) -> Generated {
    let mut g = new_gen(seed ^ 0xbad);
    let count = 2 + g.rng.below(5);
    for _ in 0..count {
        g.statement();
    }
    let valid = assemble(g, seed);
    let mut rng = Rng::new(seed ^ 0xf00d);
    let mut lines: Vec<String> = valid.source.lines().map(str::to_string).collect();
    let body_start = lines
        .iter()
        .position(|l| l.starts_with("export fn main"))
        .unwrap_or(0)
        + 1;
    let at = body_start + rng.below((lines.len() - body_start) as u64) as usize;
    let line = lines[at].clone();
    let chars: Vec<char> = line.chars().collect();
    let mutated = match rng.below(9) {
        0 => String::new(),
        1 if !chars.is_empty() => {
            let i = rng.below(chars.len() as u64) as usize;
            chars
                .iter()
                .enumerate()
                .filter(|(j, _)| *j != i)
                .map(|(_, c)| c)
                .collect()
        }
        2 => format!("{line})"),
        3 => format!("{line} +"),
        4 => format!("  {line}"),
        5 => line.replacen('(', "", 1),
        6 => line.replacen('"', "", 1),
        7 => format!("{line}:"),
        _ => line.replace(" = ", " == "),
    };
    lines[at] = mutated;
    let mut tags = vec!["fuzz", "parser", "diagnostics", "layout"];
    tags.sort_unstable();
    Generated {
        source: lines.join("\n") + "\n",
        tags,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rng_is_reproducible() {
        let a: Vec<u64> = (0..5).map(|_| 0).collect();
        let mut r1 = Rng::new(7);
        let mut r2 = Rng::new(7);
        let x: Vec<u64> = a.iter().map(|_| r1.next_u64()).collect();
        let y: Vec<u64> = a.iter().map(|_| r2.next_u64()).collect();
        assert_eq!(x, y);
        assert_ne!(Rng::new(8).next_u64(), Rng::new(7).next_u64());
    }

    #[test]
    fn programs_are_deterministic_and_vary() {
        assert_eq!(program(3).source, program(3).source);
        assert_ne!(program(3).source, program(4).source);
        assert!(program(3).source.contains("export def main() -> Int: ..."));
        assert!(type_error(1).source.contains("export fn main"));
        assert!(!syntax_error(2).source.is_empty());
    }

    #[test]
    fn escaped_length_counts_characters() {
        assert_eq!(escaped_len("a\\tb"), 3);
        assert_eq!(escaped_len("日本語"), 3);
        assert_eq!(escaped_len("q\\\"d"), 3);
    }

    #[test]
    fn int_codes_nest() {
        assert_eq!(int_code(-5), "(-5)");
        assert_eq!(int_code(i64::MIN), "(-9223372036854775808)");
        assert_eq!(int_code(7), "7");
    }
}
