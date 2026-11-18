// Idiomatic Rust for the whole-program kernels, mirroring go/main.go. Standard library only.
use std::collections::HashMap;
use std::hint::black_box;
use std::time::Instant;

struct Body {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
}

struct Grid {
    width: usize,
    height: usize,
    cells: Vec<i64>,
}

struct Tree {
    l: Option<Box<Tree>>,
    r: Option<Box<Tree>>,
}

fn sieve(n: usize) -> i64 {
    let mut flags: Vec<bool> = Vec::new();
    for _ in 0..=n {
        flags.push(true);
    }
    let mut count = 0;
    for i in 2..=n {
        if flags[i] {
            count += 1;
            let mut j = i * i;
            while j <= n {
                flags[j] = false;
                j += i;
            }
        }
    }
    count
}

fn advance(b: &mut [Body], steps: usize) -> f64 {
    let n = b.len();
    for _ in 0..steps {
        for i in 0..n {
            for j in i + 1..n {
                let (head, tail) = b.split_at_mut(j);
                let a = &mut head[i];
                let c = &mut tail[0];
                let (dx, dy, dz) = (a.x - c.x, a.y - c.y, a.z - c.z);
                let d2 = dx * dx + dy * dy + dz * dz + 0.01;
                let mag = 0.01 / (d2 * d2);
                a.vx -= dx * c.mass * mag;
                a.vy -= dy * c.mass * mag;
                a.vz -= dz * c.mass * mag;
                c.vx += dx * a.mass * mag;
                c.vy += dy * a.mass * mag;
                c.vz += dz * a.mass * mag;
            }
        }
        for a in b.iter_mut() {
            a.x += 0.01 * a.vx;
            a.y += 0.01 * a.vy;
            a.z += 0.01 * a.vz;
        }
    }
    let mut e = 0.0;
    for a in b.iter() {
        e += a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz);
    }
    e
}

fn cell(g: &Grid, x: i64, y: i64) -> i64 {
    let (w, h) = (g.width as i64, g.height as i64);
    let wx = (x + w) % w;
    let wy = (y + h) % h;
    g.cells[(wy * w + wx) as usize]
}

fn neighbors(g: &Grid, x: i64, y: i64) -> i64 {
    let mut n = 0;
    for dy in -1..=1 {
        for dx in -1..=1 {
            if !(dx == 0 && dy == 0) {
                n += cell(g, x + dx, y + dy);
            }
        }
    }
    n
}

fn step(g: &Grid) -> Grid {
    let mut next = Vec::new();
    for y in 0..g.height as i64 {
        for x in 0..g.width as i64 {
            let n = neighbors(g, x, y);
            let alive = cell(g, x, y) == 1;
            next.push(if n == 3 || (alive && n == 2) { 1 } else { 0 });
        }
    }
    Grid { width: g.width, height: g.height, cells: next }
}

fn life(gens: usize) -> i64 {
    let mut cells = Vec::new();
    for i in 0..128 * 128 {
        cells.push(if i % 7 == 0 || i % 11 == 0 { 1 } else { 0 });
    }
    let mut g = Grid { width: 128, height: 128, cells };
    for _ in 0..gens {
        g = step(&g);
    }
    g.cells.iter().sum()
}

fn matmul(n: usize) -> f64 {
    let mut a: Vec<Vec<f64>> = Vec::new();
    let mut b: Vec<Vec<f64>> = Vec::new();
    for i in 0..n as i64 {
        let mut ra = Vec::new();
        let mut rb = Vec::new();
        for j in 0..n as i64 {
            ra.push((i + j) as f64);
            rb.push((i - j) as f64);
        }
        a.push(ra);
        b.push(rb);
    }
    let mut total = 0.0;
    for i in 0..n {
        for j in 0..n {
            let mut s = 0.0;
            for k in 0..n {
                s += a[i][k] * b[k][j];
            }
            total += s;
        }
    }
    total
}

fn make(d: i64) -> Option<Box<Tree>> {
    if d == 0 {
        return None;
    }
    Some(Box::new(Tree { l: make(d - 1), r: make(d - 1) }))
}

fn check(t: &Option<Box<Tree>>) -> i64 {
    match t {
        None => 1,
        Some(t) => 1 + check(&t.l) + check(&t.r),
    }
}

fn trees(r: i64) -> i64 {
    let mut t = 0;
    for _ in 0..r {
        t += check(&make(16));
    }
    t
}

fn collatz(limit: i64) -> i64 {
    let mut best = 0;
    for n in 1..limit {
        let (mut x, mut steps) = (n, 0);
        while x != 1 {
            if x % 2 == 0 {
                x /= 2;
            } else {
                x = 3 * x + 1;
            }
            steps += 1;
        }
        if steps > best {
            best = steps;
        }
    }
    best
}

fn wordfreq(n: i64) -> i64 {
    let mut m: HashMap<i64, i64> = HashMap::new();
    for i in 0..n {
        *m.entry((i * 7919) % 5003).or_insert(0) += 1;
    }
    m.len() as i64
}

#[derive(Clone, Copy)]
struct Cx {
    re: f64,
    im: f64,
}

impl Cx {
    fn mul(self, o: Cx) -> Cx {
        Cx { re: self.re * o.re - self.im * o.im, im: self.re * o.im + self.im * o.re }
    }
    fn add(self, o: Cx) -> Cx {
        Cx { re: self.re + o.re, im: self.im + o.im }
    }
    fn norm2(self) -> f64 {
        self.re * self.re + self.im * self.im
    }
}

fn mandel(n: i64) -> i64 {
    let mut total = 0;
    for y in 0..n {
        for x in 0..n {
            let c = Cx { re: 3.0 * x as f64 / n as f64 - 2.0, im: 2.0 * y as f64 / n as f64 - 1.0 };
            let mut z = Cx { re: 0.0, im: 0.0 };
            let mut i = 0;
            while i < 100 && z.norm2() < 4.0 {
                z = z.mul(z).add(c);
                i += 1;
            }
            total += i;
        }
    }
    total
}

#[derive(Clone)]
struct Particle {
    x: f64,
    y: f64,
    vx: f64,
    vy: f64,
}

fn particles(n: usize, steps: usize) -> i64 {
    let mut ps: Vec<Particle> = Vec::new();
    for i in 0..n {
        let f = i as f64;
        ps.push(Particle { x: f, y: f * 0.5, vx: 1.0, vy: -1.0 });
    }
    for _ in 0..steps {
        for i in 0..n {
            let mut p = ps[i].clone();
            p.x += p.vx * 0.01;
            p.y += p.vy * 0.01;
            if p.x > 100.0 {
                p.vx = -p.vx;
            }
            ps[i] = p;
        }
    }
    let mut e = 0.0;
    for p in &ps {
        e += p.x + p.y;
    }
    e as i64
}

enum Op {
    Push(i64),
    #[allow(dead_code)]
    Add,
    Mul,
    #[allow(dead_code)]
    Dup,
    #[allow(dead_code)]
    Swap,
    Pop,
    JmpNz(usize),
    Dec,
}

fn vm(iters: i64) -> i64 {
    let code = [Op::Push(3), Op::Push(7), Op::Mul, Op::Pop, Op::Dec, Op::JmpNz(0), Op::Pop];
    let mut stack: Vec<i64> = vec![iters];
    let (mut pc, mut acc) = (0, 0);
    while pc < code.len() {
        match &code[pc] {
            Op::Push(n) => {
                stack.push(*n);
                pc += 1;
            }
            Op::Add => {
                let b = stack.pop().unwrap_or(0);
                let a = stack.pop().unwrap_or(0);
                stack.push(a + b);
                pc += 1;
            }
            Op::Mul => {
                let b = stack.pop().unwrap_or(0);
                let a = stack.pop().unwrap_or(0);
                stack.push(a * b % 1000003);
                pc += 1;
            }
            Op::Dup => {
                let v = stack[stack.len() - 1];
                stack.push(v);
                pc += 1;
            }
            Op::Swap => {
                let b = stack.pop().unwrap_or(0);
                let a = stack.pop().unwrap_or(0);
                stack.push(b);
                stack.push(a);
                pc += 1;
            }
            Op::Pop => {
                acc += stack.pop().unwrap_or(0);
                pc += 1;
            }
            Op::JmpNz(t) => {
                if stack[stack.len() - 1] != 0 {
                    pc = *t;
                } else {
                    pc += 1;
                }
            }
            Op::Dec => {
                let v = stack.pop().unwrap_or(0);
                stack.push(v - 1);
                pc += 1;
            }
        }
    }
    acc
}

enum Expr {
    Num(i64),
    Add(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
}

fn build(d: i64, s: i64) -> Expr {
    if d == 0 {
        return Expr::Num(s % 10);
    }
    if d % 2 == 0 {
        return Expr::Add(Box::new(build(d - 1, s * 3 + 1)), Box::new(build(d - 1, s * 7 + 2)));
    }
    Expr::Mul(Box::new(build(d - 1, s + 1)), Box::new(build(d - 1, s + 3)))
}

fn eval(e: &Expr) -> i64 {
    match e {
        Expr::Num(n) => *n,
        Expr::Add(l, r) => (eval(l) + eval(r)) % 1000003,
        Expr::Mul(l, r) => eval(l) * eval(r) % 1000003,
    }
}

fn exprs(d: i64, reps: i64) -> i64 {
    let e = build(d, 1);
    let mut t = 0;
    for _ in 0..reps {
        t += eval(&e);
    }
    t
}

fn closures(n: i64) -> i64 {
    let k = 7;
    let f = |x: i64| x * k + 1;
    let mut t = 0;
    for i in 0..n {
        t += f(i) % 13;
    }
    let xs: Vec<i64> = (0..1000).map(|x| x * k).collect();
    for _ in 0..n / 1000 {
        t += xs.iter().map(|x| x + k).filter(|x| x % 3 == 0).sum::<i64>();
    }
    t
}

fn stencil(n: usize, iters: usize) -> i64 {
    let mut a = vec![0i64; n * n];
    let mut b = vec![0i64; n * n];
    for i in 0..n * n {
        a[i] = (i % 17) as i64;
    }
    for _ in 0..iters {
        for y in 1..n - 1 {
            for x in 1..n - 1 {
                let v = a[y * n + x - 1] + a[y * n + x + 1] + a[(y - 1) * n + x] + a[(y + 1) * n + x];
                b[y * n + x] = v % 1009;
            }
        }
        std::mem::swap(&mut a, &mut b);
    }
    a.iter().sum()
}

// black_box keeps the compiler from folding a whole kernel at compile time.
fn timed(name: &str, f: impl FnOnce() -> i64) {
    let t = Instant::now();
    let r = f();
    println!("{name} {} {r}", t.elapsed().as_micros());
}

fn main() {
    timed("sieve_5M", || sieve(black_box(5000000)));
    timed("nbody_200k", || {
        let mut b = vec![
            Body { x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: 10.0 },
            Body { x: 1.0, y: 0.0, z: 0.0, vx: 0.0, vy: 1.0, vz: 0.0, mass: 1.0 },
            Body { x: 0.0, y: 2.0, z: 0.0, vx: 1.0, vy: 0.0, vz: 0.0, mass: 1.0 },
            Body { x: 0.0, y: 0.0, z: 3.0, vx: 0.0, vy: 0.0, vz: 1.0, mass: 1.0 },
            Body { x: 4.0, y: 4.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: 0.5 },
        ];
        (advance(&mut b, black_box(200000)) * 1000.0) as i64
    });
    timed("life_128x128_50", || life(black_box(50)));
    timed("matmul_200", || matmul(black_box(200)) as i64);
    timed("trees_d16_x20", || trees(black_box(20)));
    timed("collatz_1M", || collatz(black_box(1000000)));
    timed("map_count_2M", || wordfreq(black_box(2000000)));
    timed("mandel_400", || mandel(black_box(400)));
    timed("particles_1k_5k", || particles(black_box(1000), black_box(5000)));
    timed("vm_5M", || vm(black_box(5000000)));
    timed("expr_d20_x20", || exprs(black_box(20), black_box(20)));
    timed("closures_20M", || closures(black_box(20000000)));
    timed("stencil_1000_20", || stencil(black_box(1000), black_box(20)));
}
