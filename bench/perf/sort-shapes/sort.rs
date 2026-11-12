use std::borrow::Cow;
use std::time::Instant;
#[derive(Clone)] struct Event { id: i64, kind: i64, #[allow(dead_code)] name: Cow<'static, str>, #[allow(dead_code)] score: i64 }
#[derive(Clone)] struct Plain { id: i64, kind: i64, #[allow(dead_code)] score: i64 }
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn events(n: i64, m: i64) -> Vec<Event> { let mut x = 1; (0..n).map(|i| { x = lcg(x); Event { id: i, kind: x % m, name: Cow::Borrowed("an-event-name-over-sixteen-bytes"), score: i % 13 } }).collect() }
fn plains(n: i64, m: i64) -> Vec<Plain> { let mut x = 1; (0..n).map(|i| { x = lcg(x); Plain { id: i, kind: x % m, score: i % 13 } }).collect() }
fn us(t: Instant) -> u128 { t.elapsed().as_micros() }
fn main() {
    let n = 1000000usize;
    let a = events(n as i64, 1000);
    let t = Instant::now(); let mut b = a.clone(); b.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("owned-dups-sorted {} {}", e, b[0].kind + b[n-1].kind + b[1000].id % 7);
    let mut c = events(n as i64, 1000);
    let t = Instant::now(); c.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("owned-dups-inplace {} {}", e, c[0].kind + c[n-1].kind + c[1000].id % 7);
    let d = events(n as i64, 1000000000);
    let t = Instant::now(); let mut e2 = d.clone(); e2.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("owned-distinct-sorted {} {}", e, e2[0].kind + e2[n-1].kind + e2[1000].id % 7);
    let f = plains(n as i64, 1000);
    let t = Instant::now(); let mut g = f.clone(); g.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("plain-dups-sorted {} {}", e, g[0].kind + g[n-1].kind + g[1000].id % 7);
    let h = plains(n as i64, 1000000000);
    let t = Instant::now(); let mut i = h.clone(); i.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("plain-distinct-sorted {} {}", e, i[0].kind + i[n-1].kind + i[1000].id % 7);
    let s: Vec<Plain> = (0..n as i64).map(|k| Plain { id: k, kind: k / 4 + (k % 3), score: 0 }).collect();
    let t = Instant::now(); let mut r = s.clone(); r.sort_by(|p, q| p.kind.cmp(&q.kind)); let e = us(t);
    println!("plain-nearly-sorted {} {}", e, r[0].kind + r[n-1].kind + r[1000].id % 7);
}
