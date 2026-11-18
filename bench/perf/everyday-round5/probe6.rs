use std::time::Instant;
enum Tree { Leaf(i64), Node(Box<Tree>, Box<Tree>) }
enum Cons { Nil, Cell(i64, Box<Cons>) }
trait Shape { fn area(&self) -> i64; }
struct Sq(i64); struct Rc(i64, i64);
impl Shape for Sq { fn area(&self) -> i64 { self.0 * self.0 } }
impl Shape for Rc { fn area(&self) -> i64 { self.0 * self.1 } }
fn make(i: i64) -> Box<dyn Shape> { if i % 2 == 0 { Box::new(Sq(i % 10)) } else { Box::new(Rc(i % 7, i % 5)) } }
fn mk(depth: i64, v: i64) -> Tree { if depth == 0 { return Tree::Leaf(v) } Tree::Node(Box::new(mk(depth - 1, v * 2)), Box::new(mk(depth - 1, v * 2 + 1))) }
fn sum(t: &Tree) -> i64 { match t { Tree::Leaf(v) => *v, Tree::Node(l, r) => (sum(l) + sum(r)) % 1000003 } }
fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }
fn q_tree() -> i64 { let mut t = 0; for r in 0..5 { let tree = mk(20, r + 1); t += sum(&tree); } t }
fn q_iface_alloc() -> i64 { let mut t = 0; for i in 0..10000000 { let s = make(i); t += s.area(); } t }
fn q_small_list_map() -> i64 { let mut t = 0; for i in 0..2000000i64 { let k = i % 5 + 1; let v: Vec<i64> = vec![i, i + 1, i + 2].iter().map(|v| v * k).collect(); t += v.iter().sum::<i64>(); } t }
fn q_closure_capture_list() -> i64 { let mut fs: Vec<Box<dyn Fn(i64) -> i64>> = Vec::new(); for i in 0..1000000i64 { let k = i % 9; fs.push(Box::new(move |v| v + k)); } let mut t = 0; for r in 0..10 { for f in &fs { t += f(r); } } t }
fn q_cons() -> i64 { let mut c = Cons::Nil; for i in 0..1000000 { c = Cons::Cell(i, Box::new(c)); } let mut t = 0; let mut cur = &c; while let Cons::Cell(h, rest) = cur { t += h; cur = rest; } std::mem::forget(c); t }
fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() { run("q_tree", q_tree); run("q_iface_alloc", q_iface_alloc); run("q_small_list_map", q_small_list_map); run("q_closure_capture_list", q_closure_capture_list); run("q_cons", q_cons); }
