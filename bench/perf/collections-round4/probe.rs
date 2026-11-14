use std::collections::HashSet;
use std::time::Instant;
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn n_sort_floats() -> i64 { let mut xs = Vec::new(); let mut x = 1; for _ in 0..2000000 { x = lcg(x); xs.push(x as f64 / 7.0); }
    xs.sort_by(|a, b| if a < b { std::cmp::Ordering::Less } else if a > b { std::cmp::Ordering::Greater } else { std::cmp::Ordering::Equal }); xs[0] as i64 + xs[1999999] as i64 }
fn n_sort_strings_default() -> i64 { let mut xs = Vec::new(); let mut x = 1; for _ in 0..300000 { x = lcg(x); xs.push(format!("name-{}-suffix", x % 100000)); }
    let mut ys = xs.clone(); ys.sort(); (ys[0].len() + ys[299999].len()) as i64 }
fn n_index_of_strings() -> i64 { let xs: Vec<String> = (0..2000).map(|i| format!("item-number-{}", i)).collect(); let mut t = 0;
    for i in 0..20000 { let k = format!("item-number-{}", i % 2000); t += xs.iter().position(|s| *s == k).unwrap_or(0) as i64; } t }
fn n_remove_front() -> i64 { let mut xs: Vec<i64> = (0..100000).collect(); let mut t = 0; while !xs.is_empty() { xs.remove(0); t += 1; } t }
fn n_min_max_sum() -> i64 { let xs: Vec<i64> = (0..3000000).map(|i| (i * 7919) % 100003).collect(); let (mut lo, mut hi, mut s) = (xs[0], xs[0], 0);
    for &v in &xs { if v < lo { lo = v } if v > hi { hi = v } s += v; } lo + hi + s }
fn n_windows() -> i64 { let xs: Vec<i64> = (0..1000000).map(|i| i % 100).collect(); let mut t = 0; for i in 0..xs.len() - 3 { t += xs[i] + xs[i+1] * xs[i+2] - xs[i+3]; } t }
fn n_dedupe_sorted() -> i64 { let mut xs = Vec::new(); let mut x = 1; for _ in 0..1000000 { x = lcg(x); xs.push(x % 50000); }
    let mut ys = xs.clone(); ys.sort_by(|a, b| (a - b).cmp(&0)); let mut out: Vec<i64> = Vec::new(); for v in ys { if out.is_empty() || *out.last().unwrap() != v { out.push(v); } } out.len() as i64 }
fn n_list_clone_modify() -> i64 { let base: Vec<Vec<i64>> = (0..1000).map(|i| (0..100).map(|j| i + j).collect()).collect(); let mut t = 0;
    for k in 0..200 { let mut c = base.clone(); c[k][0] = 99; t += c[k][0] + c.len() as i64; } t }
fn n_closure_list() -> i64 { let fs: Vec<Box<dyn Fn(i64) -> i64>> = (0..1000i64).map(|i| Box::new(move |v| v + i) as Box<dyn Fn(i64) -> i64>).collect();
    let mut t = 0; for r in 0..2000 { for f in &fs { t += f(r); } } t }
fn n_string_set_ops() -> i64 { let mut a = HashSet::new(); let mut b = HashSet::new(); for i in 0..200000 { a.insert(format!("s{}", i)); b.insert(format!("s{}", i * 2)); }
    (a.intersection(&b).count() + a.union(&b).count()) as i64 }
fn run(n: &str, f: fn() -> i64) { let t = Instant::now(); let c = f(); println!("{} {} {}", n, t.elapsed().as_micros(), c); }
fn main() {
    run("n_sort_floats", n_sort_floats); run("n_sort_strings_default", n_sort_strings_default); run("n_index_of_strings", n_index_of_strings);
    run("n_remove_front", n_remove_front); run("n_min_max_sum", n_min_max_sum); run("n_windows", n_windows); run("n_dedupe_sorted", n_dedupe_sorted);
    run("n_list_clone_modify", n_list_clone_modify); run("n_closure_list", n_closure_list); run("n_string_set_ops", n_string_set_ops);
}
