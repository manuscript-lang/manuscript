use std::collections::{HashMap, HashSet};
use std::time::Instant;

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

struct Node { l: Option<Box<Node>>, r: Option<Box<Node>> }
struct P { x: i64, y: i64, _name: String }

fn big_int_map() -> i64 {
    let mut m: HashMap<i64, i64> = HashMap::new();
    let mut x = 1;
    for i in 0..2000000 { x = lcg(x); m.insert(x * 7919 % 4000037, i); }
    let mut t = 0;
    for _ in 0..2000000 { x = lcg(x); if let Some(v) = m.get(&(x * 7919 % 4000037)) { t += v; } }
    t + m.len() as i64
}
fn string_key_map() -> i64 {
    let mut m: HashMap<String, i64> = HashMap::new();
    for i in 0..500000 { m.insert(format!("key-number-{}", i), i); }
    let mut t = 0;
    for i in 0..500000 { t += m[&format!("key-number-{}", i)]; }
    t
}
fn map_remove_churn() -> i64 {
    let mut m: HashMap<i64, i64> = HashMap::new();
    for i in 0..1000000 { m.insert(i, i); if i >= 1000 { m.remove(&(i - 1000)); } }
    let mut t = 0;
    for (_, v) in m.iter() { t += v; }
    t + m.len() as i64
}
fn set_ops() -> i64 {
    let mut a = HashSet::new(); let mut b = HashSet::new();
    for i in 0..500000i64 { a.insert(i * 3); b.insert(i * 5); }
    let u: HashSet<i64> = a.union(&b).cloned().collect();
    let n: HashSet<i64> = a.intersection(&b).cloned().collect();
    let d: HashSet<i64> = a.difference(&b).cloned().collect();
    (u.len() + n.len() + d.len()) as i64
}
fn sort_ints() -> i64 {
    let mut xs = Vec::new(); let mut x = 1;
    for _ in 0..3000000 { x = lcg(x); xs.push(x); }
    let mut ys = xs.clone(); ys.sort_by(|a, b| (a - b).cmp(&0));
    ys[0] + ys[1500000] + ys[2999999]
}
fn sort_strings() -> i64 {
    let mut xs = Vec::new(); let mut x = 1;
    for _ in 0..500000 { x = lcg(x); xs.push(format!("s{}", x)); }
    xs.sort_by(|a, b| a.cmp(b));
    (xs[0].len() + xs[250000].len()) as i64
}
fn struct_list() -> i64 {
    let mut xs = Vec::new();
    for i in 0..1000000 { xs.push(P { x: i, y: i * 2, _name: "n".to_string() }); }
    let mut t = 0;
    for p in &xs { t += p.x + p.y; }
    let ys: Vec<i64> = xs.iter().map(|p| p.x + 1).collect();
    t + ys.len() as i64
}
fn make_tree(d: i32) -> Option<Box<Node>> {
    if d == 0 { return Some(Box::new(Node { l: None, r: None })); }
    Some(Box::new(Node { l: make_tree(d - 1), r: make_tree(d - 1) }))
}
fn count(n: &Option<Box<Node>>) -> i64 {
    match n { None => 0, Some(b) => 1 + count(&b.l) + count(&b.r) }
}
fn trees() -> i64 { let mut t = 0; for _ in 0..20 { t += count(&make_tree(18)); } t }
fn list_of_lists() -> i64 {
    let mut g: Vec<Vec<i64>> = Vec::new();
    for i in 0..1500i64 { let mut r = Vec::new(); for j in 0..1500 { r.push(i * 31 + j as i64); } g.push(r); }
    let mut t = 0;
    for i in 1..1499 { for j in 1..1499 { t += g[i-1][j] + g[i+1][j] + g[i][j-1] + g[i][j+1]; } }
    t
}
fn list_ops() -> i64 {
    let xs: Vec<i64> = (0..2000000).map(|i| i % 1000).collect();
    let mut seen = HashSet::new(); let mut d = Vec::new();
    for &v in &xs { if seen.insert(v) { d.push(v); } }
    let r: Vec<i64> = xs.iter().rev().cloned().collect();
    let s: Vec<i64> = xs.iter().filter(|v| *v % 2 == 0).map(|v| v * 3).collect();
    let mut t = 0;
    for i in 0..200 { if xs.contains(&(999 + i)) { t += 1; } }
    d.len() as i64 + r[0] + s.len() as i64 + t
}
fn run(name: &str, f: fn() -> i64) {
    let t = Instant::now(); let c = f();
    println!("{} {} {}", name, t.elapsed().as_micros(), c);
}
fn main() {
    run("big_int_map", big_int_map); run("string_key_map", string_key_map);
    run("map_remove_churn", map_remove_churn); run("set_ops", set_ops);
    run("sort_ints", sort_ints); run("sort_strings", sort_strings);
    run("struct_list", struct_list); run("trees", trees);
    run("list_of_lists", list_of_lists); run("list_ops", list_ops);
}
