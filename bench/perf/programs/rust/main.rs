// Idiomatic Rust for the single-operation programs, mirroring go/main.go. Standard library only.
// `black_box` on each iteration's operand and result is what criterion does: without it LLVM
// folds most of these loops to constants and the row would measure nothing.
use std::collections::HashMap;
use std::hint::black_box;
use std::io::{self, BufRead};
use std::time::Instant;

trait Counter {
    fn bump(&mut self, by: i64) -> i64;
}
struct Acc {
    total: i64,
}
impl Counter for Acc {
    fn bump(&mut self, by: i64) -> i64 {
        self.total += by;
        self.total
    }
}

enum Shape {
    Circle(i64),
    Square(i64),
    Tri(i64),
}

fn ident<T>(x: T) -> T {
    x
}

fn checked(n: i64) -> Result<i64, &'static str> {
    if n < 0 {
        return Err("negative");
    }
    Ok(n + 1)
}

fn chain(n: i64) -> Result<i64, &'static str> {
    let v = checked(n)?;
    Ok(v)
}

fn area(s: &Shape) -> i64 {
    match s {
        Shape::Circle(r) => r * 3,
        Shape::Square(s) => s * s,
        Shape::Tri(b) => *b,
    }
}

fn report(name: &str, ops: i64, start: Instant) {
    println!("{name} {ops} {}", start.elapsed().as_nanos());
}

fn bench_string() -> i64 {
    let t = Instant::now();
    let mut sb = String::new();
    for _ in 0..50000 {
        sb.push_str("x");
    }
    let built = black_box(sb);
    report("string_append_50k", 50000, t);
    built.len() as i64
}

fn bench_read_line() {
    let t = Instant::now();
    let mut lines = 0;
    for line in io::stdin().lock().lines() {
        if line.is_err() {
            break;
        }
        lines += 1;
    }
    report("read_line", lines, t);
}

fn bench_map() -> i64 {
    let t = Instant::now();
    let mut m: HashMap<i64, i64> = HashMap::new();
    for i in 0..8000 {
        m.insert(i, i * 2);
    }
    let mut sum = 0;
    for i in 0..8000 {
        sum += m[&i];
    }
    report("map_put_get_8k", 16000, t);
    sum
}

fn bench_int_eq() -> i64 {
    let t = Instant::now();
    let mut hits = 0;
    for i in 0..10000000i64 {
        if black_box(i) % 3 == 0 {
            hits += 1;
        }
    }
    report("int_eq", 10000000, t);
    hits
}

fn bench_generic() -> i64 {
    let t = Instant::now();
    let mut g = 0;
    for i in 0..100000000i64 {
        g += ident::<i64>(black_box(i));
    }
    report("generic_call", 100000000, t);
    g
}

fn bench_method() -> i64 {
    let t = Instant::now();
    let mut acc = Acc { total: 0 };
    let c: &mut dyn Counter = black_box(&mut acc);
    for _ in 0..100000000 {
        c.bump(1);
    }
    report("method_call", 100000000, t);
    acc.total
}

fn bench_try() -> i64 {
    let t = Instant::now();
    let mut tr = 0;
    for i in 0..100000000i64 {
        match chain(black_box(i)) {
            Ok(v) => tr += v,
            Err(_) => tr -= 1,
        }
    }
    report("try", 100000000, t);
    tr
}

fn bench_match() -> i64 {
    let t = Instant::now();
    let shapes = black_box(vec![Shape::Circle(2), Shape::Square(3), Shape::Tri(4)]);
    let mut ma = 0;
    for i in 0..100000000usize {
        ma += area(&shapes[black_box(i) % 3]);
    }
    report("match", 100000000, t);
    ma
}

fn bench_length() -> i64 {
    let mut xs: Vec<i64> = Vec::new();
    for i in 0..100 {
        xs.push(i);
    }
    let xs = black_box(xs);
    let t = Instant::now();
    let mut ln = 0;
    for _ in 0..100000000 {
        ln += black_box(xs.len()) as i64;
    }
    report("builtin_length", 100000000, t);
    ln
}

fn bench_for_list() -> i64 {
    let mut big: Vec<i64> = Vec::new();
    for i in 0..1000000 {
        big.push(i);
    }
    let big = black_box(big);
    let t = Instant::now();
    let mut fs = 0;
    for _ in 0..100 {
        for x in big.iter() {
            fs += *x;
        }
        black_box(fs);
    }
    report("for_list", 100000000, t);
    fs
}

fn main() {
    let built = bench_string();
    bench_read_line();
    let sum = bench_map();
    let hits = bench_int_eq();
    let g = bench_generic();
    let total = bench_method();
    let tr = bench_try();
    let ma = bench_match();
    let ln = bench_length();
    let fs = bench_for_list();
    println!("# sink {built} {sum} {hits} {g} {total} {tr} {ma} {ln} {fs}");
}
