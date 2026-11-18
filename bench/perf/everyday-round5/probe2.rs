use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::time::Instant;

enum Expr { Num(i64), Add(Box<Expr>, Box<Expr>), Mul(Box<Expr>, Box<Expr>), Neg(Box<Expr>) }
fn build(depth: i64, seed: i64) -> Expr {
    if depth == 0 { return Expr::Num(seed % 10) }
    if seed % 3 == 0 { return Expr::Add(Box::new(build(depth - 1, seed * 7 + 1)), Box::new(build(depth - 1, seed * 5 + 2))) }
    if seed % 3 == 1 { return Expr::Mul(Box::new(build(depth - 1, seed * 3 + 1)), Box::new(build(depth - 1, seed + 4))) }
    Expr::Neg(Box::new(build(depth - 1, seed + 9)))
}
fn eval(e: &Expr) -> i64 { match e { Expr::Num(v) => *v, Expr::Add(l, r) => (eval(l) + eval(r)) % 1000003, Expr::Mul(l, r) => (eval(l) * eval(r)) % 1000003, Expr::Neg(i) => 0 - eval(i) } }
fn count(e: &Expr) -> i64 { match e { Expr::Num(_) => 1, Expr::Add(l, r) | Expr::Mul(l, r) => 1 + count(l) + count(r), Expr::Neg(i) => 1 + count(i) } }

#[derive(Clone, Copy, PartialEq, Eq)]
struct Item { score: i64, id: i64 }
impl Ord for Item { fn cmp(&self, o: &Item) -> std::cmp::Ordering { self.score.cmp(&o.score).then(self.id.cmp(&o.id)) } }
impl PartialOrd for Item { fn partial_cmp(&self, o: &Item) -> Option<std::cmp::Ordering> { Some(self.cmp(o)) } }
#[derive(Clone, Copy)]
struct Particle { x: f64, y: f64, vx: f64, vy: f64 }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }

fn x_expr() -> i64 { let e = build(20, 1); let mut t = count(&e); for _ in 0..10 { t += eval(&e); } t }
fn x_sort_custom() -> i64 { let mut xs = Vec::new(); let mut x = 1; for i in 0..1000000 { x = lcg(x); xs.push(Item { score: x % 5000, id: i }); } let mut ys = xs.clone(); ys.sort(); ys[0].id + ys[999999].id }
fn collatz(n: i64, memo: &mut HashMap<i64, i64>) -> i64 { if n == 1 { return 0 } if let Some(&v) = memo.get(&n) { return v } let r = 1 + collatz(if n % 2 == 0 { n / 2 } else { 3 * n + 1 }, memo); memo.insert(n, r); r }
fn x_memo() -> i64 { let mut memo = HashMap::new(); let mut t = 0; for s in 1..300000 { t += collatz(s, &mut memo); } t }
fn compose(f: Box<dyn Fn(i64) -> i64>, g: Box<dyn Fn(i64) -> i64>) -> Box<dyn Fn(i64) -> i64> { Box::new(move |v| g(f(v))) }
fn x_compose() -> i64 { let h = compose(compose(Box::new(|v| v + 1), Box::new(|v| v * 3)), Box::new(|v| v - 2)); let mut t = 0; for i in 0..30000000 { t += h(i); } t }
fn x_particles() -> i64 { let mut ps: Vec<Particle> = (0..100000).map(|i| Particle { x: i as f64, y: 0.0, vx: 1.0, vy: 0.5 }).collect(); for _ in 0..100 { for i in 0..ps.len() { ps[i].x += ps[i].vx * 0.01; ps[i].y += ps[i].vy * 0.01; if ps[i].x > 500.0 { ps[i].vx = 0.0 - ps[i].vx } } } let mut t = 0.0; for p in &ps { t += p.x + p.y; } t as i64 }
fn x_grid_stencil() -> i64 { let n = 1000usize; let g: Vec<Vec<i64>> = (0..n).map(|i| (0..n).map(|j| ((i * j) % 17) as i64).collect()).collect(); let mut t = 0; for _ in 0..5 { for i in 1..n - 1 { for j in 1..n - 1 { t += g[i - 1][j] + g[i + 1][j] + g[i][j - 1] + g[i][j + 1] - 4 * g[i][j]; } } } t }
fn x_graph_bfs() -> i64 { let n = 200000i64; let mut adj: HashMap<i64, Vec<i64>> = HashMap::new(); for i in 0..n { adj.insert(i, vec![(i * 7 + 1) % n, (i * 13 + 5) % n, (i + 1) % n]); } let mut seen = HashSet::new(); let mut frontier = vec![0i64]; seen.insert(0); let mut t = 0; while !frontier.is_empty() { let mut next = Vec::new(); for v in &frontier { for w in &adj[v] { if !seen.contains(w) { seen.insert(*w); next.push(*w); } } } t += next.len() as i64; frontier = next; } t + seen.len() as i64 }
fn x_dijkstra() -> i64 { let n = 400i64; let mut dist = vec![1000000000i64; (n * n) as usize]; let mut pq = BinaryHeap::new(); dist[0] = 0; pq.push(Reverse(Item { score: 0, id: 0 })); while let Some(Reverse(it)) = pq.pop() { if it.score > dist[it.id as usize] { continue } let x = it.id % n; let y = it.id / n; for k in 0..4 { let nx = if k == 0 { x - 1 } else if k == 1 { x + 1 } else { x }; let ny = if k == 2 { y - 1 } else if k == 3 { y + 1 } else { y }; if nx < 0 || ny < 0 || nx >= n || ny >= n { continue } let w = (nx * 31 + ny * 17) % 9 + 1; let nd = it.score + w; let at = (ny * n + nx) as usize; if nd < dist[at] { dist[at] = nd; pq.push(Reverse(Item { score: nd, id: at as i64 })); } } } dist[(n * n - 1) as usize] }
fn x_map_records() -> i64 { let mut m: HashMap<String, Item> = HashMap::new(); for i in 0..300000i64 { let k = format!("key-{}", i % 5000); if let Some(c) = m.get_mut(&k) { c.score += i % 7; c.id += 1; } else { m.insert(k, Item { score: i % 7, id: 1 }); } } m.values().map(|v| v.score * v.id).sum() }
fn stage1(v: i64) -> Result<i64, String> { if v % 100003 == 0 { return Err("s1".into()) } Ok(v + 1) }
fn stage2(v: i64) -> Result<i64, String> { if v % 100019 == 0 { return Err("s2".into()) } Ok(v * 2) }
fn stage3(v: i64) -> Result<i64, String> { Ok(v - 3) }
fn pipeline(v: i64) -> Result<i64, String> { let a = stage1(v)?; let b = stage2(a)?; stage3(b) }
fn x_result_pipeline() -> i64 { let mut t = 0; for i in 1..5000000 { match pipeline(i) { Ok(v) => t += v, Err(_) => t += 1 } } t }
fn x_find_first() -> i64 { let xs: Vec<Item> = (0..1000).map(|i| Item { score: i, id: i }).collect(); let mut t = 0; for i in 0..20000 { if let Some(f) = xs.iter().find(|it| it.score == i % 1000) { t += f.id } } t }

fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() {
    run("x_expr", x_expr); run("x_sort_custom", x_sort_custom); run("x_memo", x_memo); run("x_compose", x_compose); run("x_particles", x_particles);
    run("x_grid_stencil", x_grid_stencil); run("x_graph_bfs", x_graph_bfs); run("x_dijkstra", x_dijkstra); run("x_map_records", x_map_records);
    run("x_result_pipeline", x_result_pipeline); run("x_find_first", x_find_first);
}
