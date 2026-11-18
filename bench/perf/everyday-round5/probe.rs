use std::collections::{BTreeMap, HashMap, HashSet};
use std::hint::black_box;
use std::time::Instant;

#[derive(Clone, Copy)]
struct V3 { x: i64, y: i64, z: i64 }
impl V3 {
    fn add(self, o: V3) -> V3 { V3 { x: self.x + o.x, y: self.y + o.y, z: self.z + o.z } }
    fn dot(self, o: V3) -> i64 { self.x * o.x + self.y * o.y + self.z * o.z }
}
trait Shape { fn area(&self) -> i64; }
struct Sq(i64); struct Rc(i64, i64); struct Ci(i64);
impl Shape for Sq { fn area(&self) -> i64 { self.0 * self.0 } }
impl Shape for Rc { fn area(&self) -> i64 { self.0 * self.1 } }
impl Shape for Ci { fn area(&self) -> i64 { 3 * self.0 * self.0 } }
enum Op { Push(i64), Add, Mul, Dup, #[allow(dead_code)] Pop }
struct Stack<T> { items: Vec<T> }
impl<T> Stack<T> { fn push(&mut self, v: T) { self.items.push(v) } fn pop(&mut self) -> Option<T> { self.items.pop() } }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }
fn ints(n: usize) -> Vec<i64> { let mut x = 1; (0..n).map(|_| { x = lcg(x); x % 1000 }).collect() }
fn keep(v: i64) -> bool { v % 3 != 0 }
fn scale(v: i64) -> i64 { v * 3 + 1 }

fn c_chain_calls() -> i64 { let xs = ints(2000000); let mut t = 0; for _ in 0..10 { let v: Vec<i64> = xs.iter().copied().filter(|&v| keep(v)).collect(); let w: Vec<i64> = v.iter().map(|&v| scale(v)).collect(); t += w.iter().sum::<i64>(); } t }
fn c_chain_capture() -> i64 { let xs = ints(2000000); let mut t = 0; for r in 0..10 { let k = r + 2; let v: Vec<i64> = xs.iter().copied().filter(|v| v % k != 0).collect(); let w: Vec<i64> = v.iter().map(|v| v * k).collect(); t += w.iter().sum::<i64>(); } t }
fn c_zip_dot() -> i64 { let a = ints(1000000); let b = ints(1000000); let mut t = 0; for _ in 0..10 { let z: Vec<(i64, i64)> = a.iter().copied().zip(b.iter().copied()).collect(); let m: Vec<i64> = z.iter().map(|p| p.0 * p.1).collect(); t += m.iter().sum::<i64>(); } t }
fn c_any_all_count() -> i64 { let xs = ints(2000000); let mut t = 0; for r in 0..20 { let k = r + 1; if xs.iter().any(|&v| v == 1000 + k) { t += 1 } if xs.iter().all(|&v| v < 2000) { t += 2 } t += xs.iter().filter(|&&v| v % k == 0).count() as i64; } t }
fn c_fold_record() -> i64 { let xs = ints(2000000); let mut t = 0; for _ in 0..10 { let a = xs.iter().fold(V3 { x: 0, y: 0, z: 0 }, |acc, &v| V3 { x: acc.x + v, y: acc.y + 1, z: acc.z + v % 5 }); t += a.x + a.y + a.z; } t }
fn c_take_drop() -> i64 { let xs = ints(2000000); let mut t = 0; for r in 0..20 { let v: Vec<i64> = xs[r..].to_vec(); let w: Vec<i64> = v[..1000000.min(v.len())].to_vec(); t += w.iter().sum::<i64>(); } t }
fn c_flat_map() -> i64 { let xs = ints(500000); let mut t = 0; for _ in 0..5 { let mut out = Vec::new(); for &v in &xs { out.extend_from_slice(&[v, v + 1, v + 2]); } t += out.len() as i64; } t }
fn c_chunks_windows() -> i64 { let xs = ints(500000); let mut t = 0; for c in xs.chunks(4) { let c = c.to_vec(); t += c.iter().sum::<i64>(); } for w in xs.windows(3) { let w = w.to_vec(); t += w[0] + w[2]; } t }
fn c_closure_list() -> i64 { let mut fs: Vec<Box<dyn Fn(i64) -> i64>> = Vec::new(); for i in 0..16 { let k = i; fs.push(Box::new(move |v| v * k + 1)); } let mut t = 0; for i in 0..20000000usize { t += fs[i % 16](i as i64); } t }
fn c_closure_mut() -> i64 { let mut cnt = 0; let mut sum = 0; let xs = ints(2000000); for _ in 0..10 { xs.iter().for_each(|_| cnt += 1); for &v in &xs { sum += v; } } cnt + sum }
fn apply_n(f: &dyn Fn(i64) -> i64, n: i64) -> i64 { let mut t = 0; for i in 0..n { t += f(i); } t }
fn c_closure_passed() -> i64 { let k = 7; apply_n(&move |v| v * k + 1, 50000000) }
fn max_of<T: PartialOrd + Copy>(xs: &[T]) -> T { let mut best = xs[0]; for &v in xs { if v > best { best = v } } best }
fn g_max() -> i64 { let xs = ints(2000000); let mut t = 0; for _ in 0..20 { t += max_of(&xs); } t }
fn g_stack() -> i64 { let mut s = Stack { items: Vec::new() }; let mut t = 0; for _ in 0..20 { for i in 0..500000 { s.push(i) } for _ in 0..500000 { t += s.pop().unwrap_or(0) } } t }
fn g_map_user<T, U>(xs: &[T], f: impl Fn(&T) -> U) -> Vec<U> { let mut out = Vec::new(); for v in xs { out.push(f(v)); } out }
fn g_user_map() -> i64 { let xs = ints(2000000); let mut t = 0; for _ in 0..10 { t += g_map_user(&xs, |v| v * 2).len() as i64; } t }
fn i_shapes() -> i64 { let mut xs: Vec<Box<dyn Shape>> = Vec::new(); for i in 0..1000000i64 { if i % 3 == 0 { xs.push(Box::new(Sq(i % 10))) } else if i % 3 == 1 { xs.push(Box::new(Rc(i % 7, i % 5))) } else { xs.push(Box::new(Ci(i % 4))) } } let mut t = 0; for _ in 0..10 { for s in &xs { t += s.area(); } } t }
fn e_rpn() -> i64 { let mut prog = Vec::new(); for i in 0..1000 { prog.push(Op::Push(i % 10)); prog.push(Op::Dup); prog.push(Op::Mul); prog.push(Op::Push(1)); prog.push(Op::Add); } let mut t = 0; for _ in 0..2000 { let mut st: Vec<i64> = Vec::new(); for op in &prog { match op { Op::Push(v) => st.push(*v), Op::Add => { let b = st.pop().unwrap(); let a = st.pop().unwrap(); st.push(a + b) } Op::Mul => { let b = st.pop().unwrap(); let a = st.pop().unwrap(); st.push(a * b) } Op::Dup => st.push(st[st.len() - 1]), Op::Pop => { st.pop(); } } } t += st.len() as i64 + st[0]; } t }
fn parse_val(s: i64) -> Result<i64, String> { if s % 1000 == 999 { return Err("bad".to_string()) } Ok(s * 2) }
fn e_result_chain() -> i64 { let mut t = 0; for i in 0..10000000 { match parse_val(i) { Ok(v) => t += v, Err(_) => t -= 1 } } t }
fn e_optional_chain() -> i64 { let m: HashMap<usize, i64> = ints(1000).into_iter().enumerate().collect(); let mut t = 0; for i in 0..10000000usize { if let Some(v) = m.get(&(i % 1200)) { t += v } } t }
fn r_v3_math() -> i64 { let mut acc = V3 { x: 0, y: 0, z: 0 }; for i in 0..50000000 { acc = acc.add(V3 { x: i, y: 1, z: 2 }); } acc.dot(V3 { x: 1, y: 2, z: 3 }) }
fn mk_v3() -> Vec<V3> { let mut x = 1; (0..1000000).map(|i| { x = lcg(x); V3 { x: x % 1000, y: i, z: 0 } }).collect() }
fn r_sort_field() -> i64 { let xs = mk_v3(); let mut ys = xs.clone(); ys.sort_by_key(|p| p.x); ys[0].y + ys[999999].y }
fn r_min_by() -> i64 { let xs = mk_v3(); let mut t = 0; for _ in 0..10 { t += xs.iter().min_by_key(|p| p.x).unwrap().y + xs.iter().rev().max_by_key(|p| p.x).unwrap().y; } t }
fn m_counts() -> i64 { let xs = ints(2000000); let mut c: HashMap<i64, i64> = HashMap::new(); for v in &xs { *c.entry(*v).or_insert(0) += 1; } c.len() as i64 + c[&7] }
fn m_distinct_set() -> i64 { let xs = ints(2000000); let mut seen = HashSet::new(); let mut d = Vec::new(); for &v in &xs { if seen.insert(v) { d.push(v) } } let s: HashSet<i64> = xs.iter().copied().collect(); (d.len() + s.len()) as i64 }
fn m_partition() -> i64 { let xs = ints(2000000); let (a, b): (Vec<i64>, Vec<i64>) = xs.iter().partition(|&&v| v % 2 == 0); (a.len() + b.len()) as i64 }
fn m_set_ops() -> i64 { let a: HashSet<i64> = ints(500000).into_iter().collect(); let b: HashSet<i64> = (0..300).map(|i| i * 3).collect(); let mut t = 0; for _ in 0..20 { t += a.union(&b).copied().collect::<HashSet<i64>>().len() + a.intersection(&b).copied().collect::<HashSet<i64>>().len() + a.difference(&b).copied().collect::<HashSet<i64>>().len(); } t as i64 }
fn m_binary_search() -> i64 { let mut xs = ints(1000000); xs.sort(); let mut t = 0; for i in 0..2000000i64 { let k = i % 1000; t += xs.partition_point(|&v| v < k) as i64; } t }
fn m_group_sum() -> i64 { let xs = ints(2000000); let mut m: HashMap<i64, i64> = HashMap::new(); for &v in &xs { *m.entry(v % 500).or_insert(0) += v; } m.values().sum() }
fn m_map_of_lists() -> i64 { let xs = ints(1000000); let mut m: HashMap<i64, Vec<i64>> = HashMap::new(); for &v in &xs { m.entry(v % 1000).or_default().push(v); } m.values().map(|v| v.len() as i64).sum() }
#[allow(dead_code)] fn unused(_: BTreeMap<i64, i64>) {}

fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() {
    run("c_chain_calls", c_chain_calls); run("c_chain_capture", c_chain_capture); run("c_zip_dot", c_zip_dot); run("c_any_all_count", c_any_all_count);
    run("c_fold_record", c_fold_record); run("c_take_drop", c_take_drop); run("c_flat_map", c_flat_map); run("c_chunks_windows", c_chunks_windows);
    run("c_closure_list", c_closure_list); run("c_closure_mut", c_closure_mut); run("c_closure_passed", c_closure_passed); run("g_max", g_max);
    run("g_stack", g_stack); run("g_user_map", g_user_map); run("i_shapes", i_shapes); run("e_rpn", e_rpn); run("e_result_chain", e_result_chain);
    run("e_optional_chain", e_optional_chain); run("r_v3_math", r_v3_math); run("r_sort_field", r_sort_field); run("r_min_by", r_min_by);
    run("m_counts", m_counts); run("m_distinct_set", m_distinct_set); run("m_partition", m_partition); run("m_set_ops", m_set_ops);
    run("m_binary_search", m_binary_search); run("m_group_sum", m_group_sum); run("m_map_of_lists", m_map_of_lists);
}
