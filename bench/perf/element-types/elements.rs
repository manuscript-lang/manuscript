use std::collections::{BinaryHeap, HashMap, HashSet, VecDeque};
use std::cmp::Reverse;
use std::borrow::Cow;
use std::time::Instant;

#[derive(Clone)]
struct Event { #[allow(dead_code)] id: i64, kind: i64, name: Cow<'static, str>, score: i64 }
enum Shape { Circle(i64), Rect(i64, i64), Dot }
struct Pair<A, B> { first: A, #[allow(dead_code)] second: B }
#[derive(PartialEq, Eq, PartialOrd, Ord)]
struct Job { pri: i64, id: i64 }
#[derive(PartialEq, Eq, Hash)]
struct Pt { x: i64, y: i64 }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

fn list_records() -> i64 {
    let mut xs = Vec::new();
    for i in 0..1000000 { xs.push(Event { id: i, kind: i % 7, name: Cow::Owned(format!("an-event-name-over-sixteen-bytes-{}", i % 100)), score: i % 13 }); }
    let mut t = 0;
    for _ in 0..5 { for e in &xs { if e.kind == 3 { t += e.score + e.name.len() as i64; } } }
    t
}
fn list_enums() -> i64 {
    let mut xs = Vec::new();
    for i in 0..2000000i64 {
        match i % 3 { 0 => xs.push(Shape::Circle(i % 10)), 1 => xs.push(Shape::Rect(i % 7, i % 5)), _ => xs.push(Shape::Dot) }
    }
    let mut t = 0;
    for _ in 0..5 { for s in &xs { match s { Shape::Circle(r) => t += 3 * r * r, Shape::Rect(w, h) => t += w * h, Shape::Dot => t += 1 } } }
    t
}
fn map_records() -> i64 {
    let mut m: HashMap<i64, Event> = HashMap::new();
    let mut x = 1;
    for i in 0..1000000 {
        x = lcg(x);
        let k = x % 50000;
        m.entry(k).or_insert(Event { id: k, kind: 0, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: 0 }).score += i % 5;
    }
    m.values().map(|e| e.score).sum()
}
fn map_groups() -> i64 {
    let mut m: HashMap<String, Vec<i64>> = HashMap::new();
    let mut x = 1;
    for i in 0..1000000 { x = lcg(x); m.entry(format!("k{}", x % 5000)).or_default().push(i); }
    m.values().map(|v| v.len() as i64).sum()
}
fn find(xs: &[Event], i: i64) -> Option<Event> {
    if i % 4 == 0 { return None; }
    Some(xs[(i as usize) % xs.len()].clone())
}
fn optional_records() -> i64 {
    let xs: Vec<Event> = (0..1000).map(|i| Event { id: i, kind: i % 7, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: i % 13 }).collect();
    let mut t = 0;
    for i in 0..5000000 { if let Some(e) = find(&xs, i) { t += e.score; } }
    t
}
fn deque_records() -> i64 {
    let mut q = VecDeque::new();
    let mut t = 0;
    for i in 0..3000000 {
        q.push_back(Job { pri: i % 100, id: i });
        if i % 3 == 2 { if let Some(j) = q.pop_front() { t += j.pri; } }
    }
    t
}
fn pq_records() -> i64 {
    // FIFO among equals, like the Manuscript queue: order by (pri, id)
    let mut pq = BinaryHeap::new();
    let mut x = 1;
    let mut t = 0;
    for i in 0..1000000 {
        x = lcg(x);
        pq.push(Reverse(Job { pri: x % 100000, id: i }));
        if i % 3 == 2 { if let Some(Reverse(j)) = pq.pop() { t += j.pri; } }
    }
    t
}
fn first_of<A: Clone, B>(xs: &[Pair<A, B>]) -> Vec<A> { xs.iter().map(|p| p.first.clone()).collect() }
fn generic_pairs() -> i64 {
    let xs: Vec<Pair<i64, String>> = (0..1000000).map(|i| Pair { first: i, second: format!("v{}", i % 10) }).collect();
    let mut t = 0;
    for _ in 0..5 { for a in first_of(&xs) { t += a % 10; } }
    t
}
fn make(i: i64) -> Result<Event, String> {
    if i % 10 == 0 { return Err("bad".into()); }
    Ok(Event { id: i, kind: i % 7, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: i % 13 })
}
fn results() -> i64 {
    let mut t = 0;
    for i in 0..5000000 { if let Ok(e) = make(i) { t += e.score; } }
    t
}
fn set_records() -> i64 {
    let mut s = HashSet::new();
    let mut x = 1;
    let mut t = 0;
    for _ in 0..1000000 {
        x = lcg(x);
        let p = Pt { x: x % 1000, y: (x / 1000) % 1000 };
        if s.contains(&p) { t += 1 } else { s.insert(p); }
    }
    t + s.len() as i64
}
fn sort_records() -> i64 {
    let mut xs = Vec::new();
    let mut x = 1;
    for i in 0..500000 { x = lcg(x); xs.push(Event { id: i, kind: x % 1000, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: i % 13 }); }
    xs.sort_by(|a, b| a.kind.cmp(&b.kind));
    xs[0].kind + xs[xs.len() - 1].kind + xs[1000].id % 7
}

struct Order { #[allow(dead_code)] id: i64, tags: Vec<String>, lines: Vec<Pair<i64, i64>> }
fn records_of_lists() -> i64 {
    let mut orders = Vec::new();
    for i in 0..200000 {
        let lines = (0..4).map(|k| Pair { first: k, second: i % 7 }).collect();
        orders.push(Order { id: i, tags: vec![format!("a{}", i % 3), "b".into()], lines });
    }
    let mut t = 0;
    for _ in 0..5 { for o in &orders { for l in &o.lines { t += l.first * l.second + o.tags.len() as i64; } } }
    t
}
fn nested_generics() -> i64 {
    let mut m: HashMap<i64, Vec<Pair<i64, String>>> = HashMap::new();
    for i in 0..500000 { m.entry(i % 2000).or_default().push(Pair { first: i, second: "p".into() }); }
    let mut grid = vec![vec![0i64; 1000]; 1000];
    let mut t = 0;
    for v in m.values() { t += v.len() as i64; }
    for y in 0..1000 { for x in 0..1000 { grid[y][x] = (x * 3 + y) as i64; } }
    for y in 0..1000 { for x in 0..1000 { t += grid[y][x]; } }
    t
}
fn generic_stack() -> i64 {
    let mut s: Vec<Event> = Vec::new();
    let mut t = 0;
    for i in 0..2000000 {
        s.push(Event { id: i, kind: i % 7, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: i % 13 });
        if i % 3 == 2 { if let Some(e) = s.pop() { t += e.score; } }
    }
    t
}

fn main() {
    let cases: [(&str, fn() -> i64); 14] = [
        ("list-records", list_records), ("list-enums", list_enums), ("map-records", map_records),
        ("map-groups", map_groups), ("optional-records", optional_records), ("deque-records", deque_records),
        ("pq-records", pq_records), ("generic-pairs", generic_pairs), ("result-records", results),
        ("set-records", set_records), ("sort-records", sort_records), ("records-of-lists", records_of_lists), ("nested-generics", nested_generics), ("generic-stack", generic_stack),
    ];
    for (name, f) in cases {
        let t = Instant::now();
        let r = f();
        println!("{} {} {}", name, t.elapsed().as_micros(), r);
    }
}
