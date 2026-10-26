use std::collections::{BTreeMap, BinaryHeap, HashMap, HashSet};
use std::cmp::Reverse;
use std::time::Instant;

fn next_rand(x: i64) -> i64 {
    (x * 1103515245 + 12345) % 2147483648
}

fn report(name: &str, ops: usize, t: Instant) {
    println!("{} {} {}", name, ops, t.elapsed().as_nanos());
}

fn main() {
    let mut total: i64 = 0;
    let n: usize = 1_000_000;

    let t = Instant::now();
    let mut l: Vec<i64> = Vec::new();
    for i in 0..n {
        l.push(i as i64);
    }
    report("list_append", n, t);
    total += l.len() as i64;

    let t = Instant::now();
    let mut x = 1i64;
    let mut sum = 0i64;
    for _ in 0..n {
        x = next_rand(x);
        sum += l[(x as usize) % n];
    }
    report("list_get_random", n, t);
    total += sum;

    let mut data = Vec::with_capacity(n);
    x = 1;
    for _ in 0..n {
        x = next_rand(x);
        data.push(x);
    }
    let t = Instant::now();
    let mut s = data.clone();
    s.sort();
    report("list_sort_int", n, t);
    total += s[0];

    let m = 300_000;
    let mut recs = Vec::with_capacity(m);
    x = 1;
    for i in 0..m {
        x = next_rand(x);
        recs.push((x % 100000, i as i64));
    }
    let t = Instant::now();
    let mut rs = recs.clone();
    rs.sort_by(|a, b| a.0.cmp(&b.0));
    report("list_sort_cmp", m, t);
    total += rs[0].1;

    let t = Instant::now();
    let mut mi: HashMap<i64, i64> = HashMap::new();
    x = 1;
    for i in 0..n {
        x = next_rand(x);
        mi.insert(x, i as i64);
    }
    let mut hits = 0i64;
    x = 1;
    for _ in 0..n {
        x = next_rand(x);
        hits += mi.get(&x).copied().unwrap_or(0);
    }
    report("map_int_put_get", n * 2, t);
    total += hits;

    let k = 200_000;
    let keys: Vec<String> = (0..k).map(|i| format!("key{i}")).collect();
    let t = Instant::now();
    let mut ms: HashMap<String, i64> = HashMap::new();
    for i in 0..k {
        ms.insert(keys[i].clone(), i as i64);
    }
    hits = 0;
    for i in 0..k {
        hits += ms.get(&keys[i]).copied().unwrap_or(0);
    }
    report("map_str_put_get", k * 2, t);
    total += hits;

    let t = Instant::now();
    let mut set: HashSet<i64> = HashSet::new();
    x = 1;
    for _ in 0..n {
        x = next_rand(x);
        set.insert(x);
    }
    hits = 0;
    x = 1;
    for _ in 0..n {
        x = next_rand(x);
        if set.contains(&x) {
            hits += 1;
        }
    }
    report("set_int_add_contains", n * 2, t);
    total += hits;

    let w = 200_000;
    let t = Instant::now();
    let mut sb = String::new();
    for _ in 0..w {
        sb.push_str("word");
        sb.push_str(" ");
    }
    let parts: Vec<&str> = sb.split(' ').collect();
    let joined = parts.join("-");
    let replaced = joined.replace("word", "w");
    report("string_build_split_join_replace", w, t);
    total += (replaced.len() + parts.len()) as i64;

    let b = 4_000_000;
    let t = Instant::now();
    let mut bb: Vec<u8> = Vec::new();
    for i in 0..b {
        bb.push((i % 256) as u8);
    }
    report("bytes_append", b, t);
    total += bb.len() as i64;

    let p = 300_000;
    let t = Instant::now();
    let mut h = BinaryHeap::new();
    x = 1;
    // The enqueue number breaks ties, so equal priorities dequeue in enqueue order like PriorityQueue.
    for i in 0..p {
        x = next_rand(x);
        h.push(Reverse((x, i)));
    }
    sum = 0;
    for _ in 0..p {
        sum += h.pop().unwrap().0 .0;
    }
    report("pq_int_enqueue_dequeue", p * 2, t);
    total += sum;

    let t = Instant::now();
    let mut bm: BTreeMap<i64, i64> = BTreeMap::new();
    x = 1;
    for i in 0..p {
        x = next_rand(x);
        bm.insert(x, i as i64);
    }
    hits = 0;
    x = 1;
    for _ in 0..p {
        x = next_rand(x);
        if bm.contains_key(&x) {
            hits += 1;
        }
    }
    report("sorted_map_add_contains", p * 2, t);
    total += hits;
    if total == 0 {
        println!("zero");
    }
}
