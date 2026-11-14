use std::collections::{HashMap, HashSet, BinaryHeap};
use std::cmp::Reverse;
use std::time::Instant;
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
struct Rec { id: i64, name: String, tags: Vec<String> }
impl Clone for Rec { fn clone(&self) -> Rec { Rec { id: self.id, name: self.name.clone(), tags: self.tags.clone() } } }
fn base() -> Vec<i64> { (0..2000000).map(|i| i % 1000).collect() }
fn l_distinct() -> i64 { let mut s = HashSet::new(); let mut d = Vec::new(); for v in base() { if s.insert(v) { d.push(v); } } d.len() as i64 }
fn l_reversed() -> i64 { let r: Vec<i64> = base().into_iter().rev().collect(); r[0] }
fn l_filter_map() -> i64 { base().iter().filter(|v| *v % 2 == 0).map(|v| v * 3).collect::<Vec<_>>().len() as i64 }
fn l_contains() -> i64 { let xs = base(); let mut t = 0; for i in 0..200 { if xs.contains(&(999 + i)) { t += 1; } } t }
fn l_clone_nested() -> i64 {
    let mut rs = Vec::new();
    for i in 0..200000 { rs.push(Rec { id: i, name: format!("name-{}", i), tags: vec!["a".into(), "b".into(), "c".into()] }); }
    let mut t = 0; for k in 0..5 { let c = rs.clone(); t += c.len() as i64 + c[k].tags.len() as i64 + c[k].id * 0; } t
}
fn l_insert_remove() -> i64 {
    let mut xs: Vec<i64> = Vec::new();
    for i in 0..50000 { let at = xs.len() / 2; xs.insert(at, i); }
    let mut t = 0;
    while !xs.is_empty() { let at = xs.len() / 3; xs.remove(at); t += 1; }
    t
}
fn l_sort_records_str() -> i64 {
    let mut rs = Vec::new(); let mut x = 1;
    for i in 0..300000 { x = lcg(x); rs.push(Rec { id: i, name: format!("user-name-{}", x), tags: vec![] }); }
    rs.sort_by(|a, b| a.name.cmp(&b.name));
    rs[0].id + rs[299999].id
}
fn l_group_words() -> i64 {
    let mut m: HashMap<String, Vec<i64>> = HashMap::new(); let mut x = 1;
    for i in 0..1000000 { x = lcg(x); let k = format!("w{}", x % 20000); m.entry(k).or_default().push(i); }
    let mut t = 0; for (_, v) in m.iter() { t += v.len() as i64; } t
}
fn l_map_keys_sorted() -> i64 {
    let mut m: HashMap<i64, i64> = HashMap::new();
    for i in 0..500000 { m.insert(i * 7 % 1000003, i); }
    let mut ks: Vec<i64> = m.keys().cloned().collect(); ks.sort(); ks[0] + ks[499999]
}
fn l_pq() -> i64 {
    let mut q = BinaryHeap::new(); let mut x = 1;
    for _ in 0..500000 { x = lcg(x); q.push(Reverse(x)); }
    let mut t = 0; while let Some(Reverse(v)) = q.pop() { t += v % 7; } t
}
fn l_join_split() -> i64 {
    let parts: Vec<String> = (0..500000).map(|i| format!("item{}", i)).collect();
    let s = parts.join(","); let back: Vec<&str> = s.split(',').collect(); (back.len() + s.len()) as i64
}
fn l_slices() -> i64 { let xs = base(); let mut t = 0; for i in 0..2000 { t += xs[i..i + 5000].to_vec().len() as i64; } t }
fn l_enumerate_zip() -> i64 { let xs = base(); let mut t = 0; for (i, v) in xs.iter().enumerate() { t += i as i64 * v % 7; } t }
fn l_set_strings() -> i64 { let mut s = HashSet::new(); for i in 0..500000 { s.insert(format!("str-{}", i % 100000)); } s.len() as i64 }
fn l_flatten() -> i64 { let ll: Vec<Vec<i64>> = (0..200000).map(|i| vec![i, i + 1, i + 2, i + 3]).collect(); ll.into_iter().flatten().collect::<Vec<_>>().len() as i64 }
fn run(n: &str, f: fn() -> i64) { let t = Instant::now(); let c = f(); println!("{} {} {}", n, t.elapsed().as_micros(), c); }
fn main() {
    run("l_distinct", l_distinct); run("l_reversed", l_reversed); run("l_filter_map", l_filter_map);
    run("l_contains", l_contains); run("l_clone_nested", l_clone_nested); run("l_insert_remove", l_insert_remove);
    run("l_sort_records_str", l_sort_records_str); run("l_group_words", l_group_words);
    run("l_map_keys_sorted", l_map_keys_sorted); run("l_pq", l_pq); run("l_join_split", l_join_split);
    run("l_slices", l_slices); run("l_enumerate_zip", l_enumerate_zip); run("l_set_strings", l_set_strings); run("l_flatten", l_flatten);
}
