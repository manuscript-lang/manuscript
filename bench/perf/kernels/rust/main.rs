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
}
