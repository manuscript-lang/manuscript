//! Folds constant arithmetic the way `ms-check`'s `constfaults.rs` does, for the C port in
//! `src/compiler/src/syntax/constfold.c` to be diffed against (`src/compiler/tests/constfold-diff.sh`). Each
//! stdin line is an expression; each output block lists, node by node in pre-order, its folded
//! value under several integer ranges, its literal kind, and the constant-fault messages.
//! `gen COUNT SEED` writes random expressions. Temporary tooling for the C rewrite: delete it
//! with the Rust checker. The functions below are copied from `constfaults.rs` with the checker
//! state removed.

use ms_syntax::ast::*;
use ms_syntax::parser::parse;
use ms_syntax::{Names, number};
use std::io::{BufRead, Write};
use std::sync::Arc;

const RANGES: [(&str, i128, i128); 5] = [
    ("Int8", -128, 127),
    ("UInt8", 0, 255),
    ("Int32", -(1 << 31), (1 << 31) - 1),
    ("Int", -(1 << 63), (1 << 63) - 1),
    ("UInt64", 0, (1 << 64) - 1),
];

fn fold(e: &Expr, range: (i128, i128)) -> Option<i128> {
    let fits = |v: i128| (range.0..=range.1).contains(&v).then_some(v);
    match &e.kind {
        ExprKind::Number(t) => number::canonical(Names::global().str(t))
            .parse::<i128>()
            .ok(),
        ExprKind::Unary { op, operand } => fold(operand, range).and_then(|v| match op {
            UnaryOp::Neg => fits(-v),
            UnaryOp::Plus => Some(v),
            _ => None,
        }),
        ExprKind::Binary { op, left, right } => {
            let a = fold(left, range);
            let b = fold(right, range);
            a.zip(b).and_then(|(a, b)| fits(apply(*op, a, b)?))
        }
        _ => None,
    }
}

fn literal_tree_fractional(e: &Expr) -> Option<bool> {
    match &e.kind {
        ExprKind::Number(t) => {
            let text = number::canonical(Names::global().str(t));
            (!number::is_decimal(&text)).then(|| number::is_fractional(&text))
        }
        ExprKind::Unary {
            op: UnaryOp::Neg | UnaryOp::Plus,
            operand,
        } => literal_tree_fractional(operand),
        ExprKind::Binary {
            op: BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem,
            left,
            right,
        } => {
            let l = literal_tree_fractional(left);
            let r = literal_tree_fractional(right);
            l.zip(r).and_then(|(l, r)| (l == r).then_some(l))
        }
        _ => None,
    }
}

fn apply(op: BinaryOp, a: i128, b: i128) -> Option<i128> {
    match op {
        BinaryOp::Add => a.checked_add(b),
        BinaryOp::Sub => a.checked_sub(b),
        BinaryOp::Mul => a.checked_mul(b),
        BinaryOp::Div => a.checked_div(b),
        BinaryOp::Rem => a.checked_rem(b),
        _ => None,
    }
}

fn constant_arithmetic(
    op: BinaryOp,
    left: &Expr,
    right: &Expr,
    ty: &str,
    range: (i128, i128),
) -> String {
    if matches!(op, BinaryOp::Div | BinaryOp::Rem) && fold(right, range) == Some(0) {
        return "division by zero always faults; guard the divisor or use a nonzero constant"
            .into();
    }
    let (Some(a), Some(b)) = (fold(left, range), fold(right, range)) else {
        return String::new();
    };
    if apply(op, a, b).is_some_and(|v| !(range.0..=range.1).contains(&v)) {
        return format!(
            "{a} {} {b} overflows {ty} and always faults; use a smaller value or a wider type such as BigInt",
            op.as_str()
        );
    }
    String::new()
}

fn constant_index(left: &Expr, index: &Expr) -> String {
    let ExprKind::List(items) = &left.kind else {
        return String::new();
    };
    let Some(i) = fold(index, (-(1 << 63), (1 << 63) - 1)) else {
        return String::new();
    };
    let len = items.len() as i128;
    if i >= len || i < -len {
        return format!(
            "index {i} is outside this list literal of {len} element(s) and always faults"
        );
    }
    String::new()
}

fn show(v: Option<i128>) -> String {
    v.map_or("-".to_string(), |v| v.to_string())
}

fn node(out: &mut String, e: &Expr) {
    let folds: Vec<String> = RANGES.iter().map(|r| show(fold(e, (r.1, r.2)))).collect();
    let kind = match literal_tree_fractional(e) {
        None => "-",
        Some(false) => "int",
        Some(true) => "frac",
    };
    out.push_str(&format!("{} {kind}\n", folds.join(" ")));
    match &e.kind {
        ExprKind::Binary { op, left, right } => {
            for (name, lo, hi) in RANGES {
                let m = constant_arithmetic(*op, left, right, name, (lo, hi));
                if !m.is_empty() {
                    out.push_str(&format!("  fault {name}: {m}\n"));
                }
            }
            node(out, left);
            node(out, right);
        }
        ExprKind::Unary { operand, .. } => node(out, operand),
        ExprKind::Index { left, index } => {
            let m = constant_index(left, index);
            if !m.is_empty() {
                out.push_str(&format!("  fault index: {m}\n"));
            }
            node(out, left);
            node(out, index);
        }
        ExprKind::List(items) => items.iter().for_each(|x| node(out, x)),
        _ => {}
    }
}

fn answer(line: &str) -> String {
    let file: Arc<str> = Arc::from("f.ms");
    let module = match parse(&file, &format!("A := {line}\n")) {
        Ok(m) => m,
        Err(d) => return format!("parse-error {}\n", d.message),
    };
    let Some(DeclKind::Const(c)) = module.decls.first().map(|d| &d.kind) else {
        return "not-constant\n".into();
    };
    let mut out = String::new();
    node(&mut out, &c.value);
    out
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

const NUMBERS: [&str; 34] = [
    "0",
    "1",
    "2",
    "3",
    "7",
    "10",
    "100",
    "127",
    "128",
    "255",
    "256",
    "2147483647",
    "2147483648",
    "9223372036854775807",
    "9223372036854775808",
    "18446744073709551615",
    "18446744073709551616",
    "170141183460469231731687303715884105727",
    "170141183460469231731687303715884105728",
    "1_000",
    "0xFF",
    "0b1010",
    "0xFFFF_FFFF_FFFF_FFFF",
    "0x1_0000_0000_0000_0000_0000",
    "0xffffffffffffffffffffffffffffffff",
    "0x1ffffffffffffffffffffffffffffffff",
    "1.5",
    "2e3",
    "1d",
    "1.5d",
    "3.0",
    "0xd",
    "0xe",
    "x",
];

fn expr(rng: &mut Rng, depth: u32) -> String {
    let pick = if depth == 0 { 0 } else { rng.below(10) };
    match pick {
        0..=2 => NUMBERS[rng.below(NUMBERS.len())].to_string(),
        3 => format!("-{}", expr(rng, depth - 1)),
        4 => format!("({})", expr(rng, depth - 1)),
        5 => format!(
            "[{}, {}][{}]",
            expr(rng, depth - 1),
            expr(rng, depth - 1),
            expr(rng, depth - 1)
        ),
        _ => {
            let op = ["+", "-", "*", "/", "%", "+", "*", "-"][rng.below(8)];
            format!("{} {op} {}", expr(rng, depth - 1), expr(rng, depth - 1))
        }
    }
}

fn generate(count: usize, seed: u64) {
    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let depth = 1 + rng.below(4) as u32;
        writeln!(out, "{}", expr(&mut rng, depth)).unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("gen") {
        generate(args[2].parse().unwrap(), args[3].parse().unwrap());
        return;
    }
    let stdin = std::io::stdin();
    let out = std::io::stdout();
    let mut out = out.lock();
    for line in stdin.lock().lines() {
        writeln!(out, "{}---", answer(&line.unwrap())).unwrap();
    }
}
