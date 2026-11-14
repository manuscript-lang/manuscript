use std::collections::{HashMap, HashSet, VecDeque};
use std::time::Instant;
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
struct Acc { _name: String, balance: i64, history: Vec<i64> }
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct Pt { x: i64, y: i64 }
enum Shape { Circle(i64), Rect(i64, i64), Tri(i64, i64, i64) }
fn m_struct_values() -> i64 {
    let mut m: HashMap<String, Acc> = HashMap::new(); let mut x = 1;
    for i in 0..1000000 { x = lcg(x); let k = format!("acct{}", x % 10000);
        let a = m.entry(k.clone()).or_insert_with(|| Acc { _name: k.clone(), balance: 0, history: vec![] });
        a.balance += i % 100; if a.history.len() < 8 { a.history.push(i); } }
    m.values().map(|a| a.balance + a.history.len() as i64).sum()
}
fn m_memo() -> i64 {
    let mut memo: HashMap<i64, i64> = HashMap::new(); let mut t = 0;
    for s in 1..300000i64 { let mut n = s; let mut steps = 0;
        while n != 1 && !memo.contains_key(&n) { if n % 2 == 0 { n /= 2 } else { n = 3 * n + 1 } steps += 1; }
        let base = if n == 1 { 0 } else { memo[&n] }; memo.insert(s, steps + base); t += memo[&s]; }
    t
}
fn m_struct_keys() -> i64 {
    let mut m: HashMap<Pt, i64> = HashMap::new();
    for i in 0..300000 { m.insert(Pt { x: i % 700, y: i / 700 }, i); }
    let mut t = 0; for i in 0..300000 { t += m[&Pt { x: i % 700, y: i / 700 }]; } t
}
fn m_enum_list() -> i64 {
    let mut xs = Vec::new();
    for i in 0..1000000i64 { xs.push(if i % 3 == 0 { Shape::Circle(i % 10) } else if i % 3 == 1 { Shape::Rect(i % 7, i % 5) } else { Shape::Tri(1, 2, 3) }); }
    let mut t = 0; for s in &xs { match s { Shape::Circle(r) => t += 3 * r * r, Shape::Rect(w, h) => t += w * h, Shape::Tri(a, b, c) => t += a + b + c } } t
}
fn m_bfs_grid() -> i64 {
    let n = 1000usize; let mut dist = vec![-1i64; n * n]; let mut q = VecDeque::new(); dist[0] = 0; q.push_back(0usize);
    while let Some(cur) = q.pop_front() { let x = cur % n; let y = cur / n; let d = dist[cur];
        if x > 0 && dist[cur - 1] < 0 { dist[cur - 1] = d + 1; q.push_back(cur - 1); }
        if x < n - 1 && dist[cur + 1] < 0 { dist[cur + 1] = d + 1; q.push_back(cur + 1); }
        if y > 0 && dist[cur - n] < 0 { dist[cur - n] = d + 1; q.push_back(cur - n); }
        if y < n - 1 && dist[cur + n] < 0 { dist[cur + n] = d + 1; q.push_back(cur + n); } }
    dist[n * n - 1]
}
fn m_sort_keyed() -> i64 {
    let mut xs = Vec::new(); let mut x = 1;
    for i in 0..1000000 { x = lcg(x); xs.push(Pt { x: x % 1000, y: i }); }
    let mut ys = xs.clone(); ys.sort_by(|a, b| (if a.x != b.x { a.x - b.x } else { a.y - b.y }).cmp(&0)); ys[0].y + ys[999999].y
}
fn m_group_by() -> i64 {
    let xs: Vec<i64> = (0..1000000).map(|i| i * 7 % 1000).collect();
    let mut g: HashMap<i64, Vec<i64>> = HashMap::new(); for v in xs { g.entry(v % 100).or_default().push(v); }
    g.len() as i64 + g[&5].len() as i64
}
fn m_fold_sum() -> i64 {
    let xs: Vec<i64> = (0..3000000).collect();
    let a = xs.iter().fold(0, |acc, v| acc + v % 3);
    let b = xs.iter().map(|v| v * 2).filter(|v| v % 3 == 0).collect::<Vec<_>>().len() as i64; a + b
}
fn m_list_of_strings() -> i64 {
    let xs: Vec<String> = (0..500000).map(|i| format!("line {} of text", i)).collect();
    let t: i64 = xs.iter().map(|s| s.len() as i64).sum();
    let ys: Vec<String> = xs.iter().map(|s| s.to_uppercase()).collect(); t + ys[499999].len() as i64
}
fn m_set_of_pts() -> i64 {
    let mut s = HashSet::new(); for i in 0..500000 { s.insert(Pt { x: i % 1000, y: i % 777 }); }
    s.iter().map(|p| p.x).sum::<i64>() + s.len() as i64
}
fn m_nested_maps() -> i64 {
    let mut m: HashMap<i64, HashMap<i64, i64>> = HashMap::new();
    for i in 0..500000 { m.entry(i % 1000).or_default().insert(i % 997, i); }
    m.values().map(|v| v.len() as i64).sum()
}
fn m_str_build_map() -> i64 {
    let mut m: HashMap<String, String> = HashMap::new();
    for i in 0..200000 { m.insert(format!("k{}", i), format!("value-{}-{}", i, i * 2)); }
    m.values().map(|v| v.len() as i64).sum()
}
fn run(n: &str, f: fn() -> i64) { let t = Instant::now(); let c = f(); println!("{} {} {}", n, t.elapsed().as_micros(), c); }
fn main() {
    run("m_struct_values", m_struct_values); run("m_memo", m_memo); run("m_struct_keys", m_struct_keys);
    run("m_enum_list", m_enum_list); run("m_bfs_grid", m_bfs_grid); run("m_sort_keyed", m_sort_keyed);
    run("m_group_by", m_group_by); run("m_fold_sum", m_fold_sum); run("m_list_of_strings", m_list_of_strings);
    run("m_set_of_pts", m_set_of_pts); run("m_nested_maps", m_nested_maps); run("m_str_build_map", m_str_build_map);
}
