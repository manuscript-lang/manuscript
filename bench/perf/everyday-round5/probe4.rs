use std::collections::{HashMap, HashSet};
use std::time::Instant;
#[derive(Clone)] struct Row { name: String, score: i64 }
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }
fn words(n: usize) -> Vec<String> { let mut x = 1; (0..n).map(|_| { x = lcg(x); format!("w{}", x % 20000) }).collect() }
fn z_top_k() -> i64 { let ws = words(1000000); let mut c: HashMap<String, i64> = HashMap::new(); for w in &ws { *c.entry(w.clone()).or_insert(0) += 1; } let mut rows: Vec<Row> = c.iter().map(|(k, v)| Row { name: k.clone(), score: *v }).collect(); rows.sort_by(|a, b| if a.score != b.score { b.score.cmp(&a.score) } else { a.name.cmp(&b.name) }); let top = &rows[..10]; top[0].score + top[9].score + c.len() as i64 }
fn z_insert_front() -> i64 { let mut xs: Vec<i64> = Vec::new(); for i in 0..30000 { xs.insert(0, i); } xs[0] + xs.len() as i64 }
fn z_concat_loop() -> i64 { let mut xs: Vec<i64> = Vec::new(); for i in 0..20000 { let mut n = xs.clone(); n.extend_from_slice(&[i, i + 1]); xs = n; } xs.len() as i64 }
fn z_contains_strings() -> i64 { let ws = words(3000); let mut t = 0; for i in 0..3000 { if ws.contains(&format!("w{}", i)) { t += 1 } } t }
fn z_remove_mid() -> i64 { let mut xs: Vec<i64> = (0..60000).collect(); let mut t = 0; while xs.len() > 10 { let m = xs.len() / 2; xs.remove(m); t += 1; } t }
fn z_distinct_strings() -> i64 { let ws = words(1000000); let mut seen = HashSet::new(); let mut d = Vec::new(); for w in &ws { if seen.insert(w.clone()) { d.push(w.clone()) } } d.len() as i64 }
fn z_group_rows() -> i64 { let rows: Vec<Row> = (0..1000000).map(|i| Row { name: format!("user{}", i % 3000), score: i % 100 }).collect(); let mut g: HashMap<String, Vec<Row>> = HashMap::new(); for r in &rows { g.entry(r.name.clone()).or_default().push(r.clone()); } g.values().map(|v| v.len() as i64).sum::<i64>() + g.len() as i64 }
fn z_keys_sorted() -> i64 { let mut m: HashMap<String, i64> = HashMap::new(); for i in 0..300000 { m.insert(format!("key{}", i), i); } let mut ks: Vec<String> = m.keys().cloned().collect(); ks.sort(); ks.len() as i64 + ks[0].len() as i64 }
fn z_reverse_extend() -> i64 { let xs: Vec<i64> = (0..2000000).collect(); let mut t = 0; for _ in 0..10 { let ys: Vec<i64> = xs.iter().rev().copied().collect(); let mut zs: Vec<i64> = Vec::new(); zs.extend(ys.iter()); t += zs[0]; } t }
fn z_slice_loop() -> i64 { let xs: Vec<i64> = (0..100000).collect(); let mut t = 0; for i in 0..2000 { let s = xs[i..i + 100].to_vec(); t += s.len() as i64; } t }
fn z_to_set_union() -> i64 { let ws = words(500000); let a: HashSet<String> = ws[..250000].iter().cloned().collect(); let b: HashSet<String> = ws[250000..].iter().cloned().collect(); let u: HashSet<String> = a.union(&b).cloned().collect(); let i: HashSet<String> = a.intersection(&b).cloned().collect(); (u.len() + i.len()) as i64 }
fn z_flatten_nested() -> i64 { let xs: Vec<Vec<i64>> = (0..200000).map(|i| vec![i, i + 1, i + 2, i + 3]).collect(); let mut t = 0; for _ in 0..10 { let f: Vec<i64> = xs.iter().flatten().copied().collect(); t += f.len() as i64; } t }
fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() { run("z_top_k", z_top_k); run("z_insert_front", z_insert_front); run("z_concat_loop", z_concat_loop); run("z_contains_strings", z_contains_strings); run("z_remove_mid", z_remove_mid); run("z_distinct_strings", z_distinct_strings); run("z_group_rows", z_group_rows); run("z_keys_sorted", z_keys_sorted); run("z_reverse_extend", z_reverse_extend); run("z_slice_loop", z_slice_loop); run("z_to_set_union", z_to_set_union); run("z_flatten_nested", z_flatten_nested); }
