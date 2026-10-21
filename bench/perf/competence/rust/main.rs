// Idiomatic Rust for the competence kernels, mirroring go/main.go. Standard library only.
use std::collections::{HashMap, HashSet};
use std::hint::black_box;
use std::time::Instant;

trait Shape {
    fn area(&self) -> i64;
}
struct Sq(i64);
struct Rect(i64, i64);
struct Tri(i64, i64);

impl Shape for Sq {
    fn area(&self) -> i64 {
        self.0 * self.0
    }
}
impl Shape for Rect {
    fn area(&self) -> i64 {
        self.0 * self.1
    }
}
impl Shape for Tri {
    fn area(&self) -> i64 {
        self.0 * self.1 / 2
    }
}

struct Item {
    key: i64,
    name: String,
}

struct Fail;

#[derive(Clone, Copy)]
struct P {
    x: i64,
    y: i64,
    vx: i64,
    vy: i64,
}

fn grid2d(n: i64) -> i64 {
    let mut g: Vec<Vec<i64>> = Vec::new();
    for i in 0..n {
        let mut row = Vec::new();
        for j in 0..n {
            row.push(i * j % 10);
        }
        g.push(row);
    }
    let mut t = 0;
    for _ in 0..20 {
        for a in 1..(n - 1) as usize {
            for b in 1..(n - 1) as usize {
                t += g[a][b] + g[a - 1][b] + g[a + 1][b];
            }
        }
    }
    t
}

fn bump(p: P) -> P {
    P { x: p.x + p.vx, y: p.y + p.vy, vx: p.vx, vy: p.vy }
}

fn structs(n: i64) -> i64 {
    let mut p = P { x: 0, y: 0, vx: 1, vy: 2 };
    for _ in 0..n {
        p = bump(p);
    }
    p.x + p.y
}

fn stack_ops(n: i64) -> i64 {
    let mut s: Vec<i64> = Vec::new();
    let mut t = 0;
    for i in 0..n {
        s.push(i);
        if i % 3 == 2 {
            t += s.pop().unwrap();
            t += s.pop().unwrap();
        }
    }
    t + s.len() as i64
}

fn optionals(n: i64) -> i64 {
    let mut t = 0;
    for i in 0..n {
        let o = if i % 5 != 0 { Some(i) } else { None };
        match o {
            Some(v) => t += v,
            None => t += 1,
        }
    }
    t
}

fn sets(n: i64) -> i64 {
    let mut s: HashSet<i64> = HashSet::new();
    for i in 0..n {
        s.insert(i * 7919 % 100003);
    }
    let mut h = 0;
    for j in 0..n {
        if s.contains(&j) {
            h += 1;
        }
    }
    h + s.len() as i64
}

fn chars(n: i64) -> i64 {
    let text = "the quick brown fox jumps over the lazy dog ";
    let mut t = 0;
    for _ in 0..n {
        for c in text.chars() {
            if c == 'o' {
                t += 1;
            }
        }
    }
    t
}

fn fib(n: i64) -> i64 {
    if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

fn dispatch(n: i64) -> i64 {
    let shapes: Vec<Box<dyn Shape>> =
        vec![Box::new(Sq(3)), Box::new(Rect(2, 5)), Box::new(Tri(4, 6)), Box::new(Sq(7))];
    let mut t = 0;
    for i in 0..n {
        t += shapes[(i % 4) as usize].area();
    }
    t
}

fn closures(n: i64) -> i64 {
    let base = 3;
    let f = |x: i64| x * base + 1;
    let mut t = 0;
    for i in 0..n {
        t += f(i);
    }
    t
}

fn sorting(n: i64) -> i64 {
    let v: Vec<i64> = (0..n).map(|i| i * 7919 % 1000003).collect();
    let mut s = v.clone();
    s.sort_by(|a, b| a.cmp(b));
    s[0] + s[(n / 2) as usize] + s[(n - 1) as usize]
}

fn text(n: i64) -> i64 {
    let mut b = String::new();
    for i in 0..n {
        b.push_str(&(i * 31 % 1000).to_string());
        b.push(',');
    }
    let mut t = 0;
    for p in b.split(',') {
        t += p.parse::<i64>().unwrap_or(0);
    }
    t
}

fn word_map(n: i64) -> i64 {
    let words: Vec<String> = (0..1000).map(|i| format!("word{i}")).collect();
    let mut m: HashMap<&str, i64> = HashMap::new();
    for j in 0..n {
        *m.entry(&words[(j * 7 % 1000) as usize]).or_insert(0) += 1;
    }
    m.len() as i64 + m.get("word7").copied().unwrap_or(0)
}

fn check(i: i64) -> Result<i64, Fail> {
    if i % 1000 == 999 { Err(Fail) } else { Ok(i) }
}

fn step(i: i64) -> Result<i64, Fail> {
    let v = check(i)?;
    Ok(v + 1)
}

fn errors(n: i64) -> i64 {
    let mut t = 0;
    for i in 0..n {
        match step(i) {
            Ok(v) => t += v,
            Err(_) => t += 7,
        }
    }
    t
}

fn records(n: i64) -> i64 {
    let mut items: Vec<Item> = Vec::new();
    for i in 0..n {
        items.push(Item { key: i * 7919 % 10007, name: format!("n{}", i % 100) });
    }
    let mut t = 0;
    for _ in 0..20 {
        for it in &items {
            t += it.key + it.name.len() as i64;
        }
    }
    t
}

// black_box keeps the compiler from folding a whole kernel at compile time.
fn timed(name: &str, f: impl FnOnce() -> i64) {
    let t = Instant::now();
    let r = f();
    println!("{name} {} {r}", t.elapsed().as_micros());
}

fn main() {
    timed("call_fib_36", || fib(black_box(36)));
    timed("dispatch_100M", || dispatch(black_box(100000000)));
    timed("closure_100M", || closures(black_box(100000000)));
    timed("sort_1M", || sorting(black_box(1000000)));
    timed("text_1M", || text(black_box(1000000)));
    timed("strmap_10M", || word_map(black_box(10000000)));
    timed("errors_50M", || errors(black_box(50000000)));
    timed("records_1M_x20", || records(black_box(1000000)));
    timed("grid2d_500x20", || grid2d(black_box(500)));
    timed("struct_100M", || structs(black_box(100000000)));
    timed("stack_20M", || stack_ops(black_box(20000000)));
    timed("optional_100M", || optionals(black_box(100000000)));
    timed("set_2M", || sets(black_box(2000000)));
    timed("chars_1M", || chars(black_box(1000000)));
}
