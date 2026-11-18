use std::time::Instant;

struct Counter { at: i64, end: i64 }
impl Iterator for Counter { type Item = i64; fn next(&mut self) -> Option<i64> { if self.at >= self.end { return None } self.at += 1; Some(self.at - 1) } }
struct Evens { inner: Box<dyn Iterator<Item = i64>> }
impl Iterator for Evens { type Item = i64; fn next(&mut self) -> Option<i64> { loop { match self.inner.next() { Some(v) => if v % 2 == 0 { return Some(v) }, None => return None } } } }
struct Scaled { inner: Box<dyn Iterator<Item = i64>>, k: i64 }
impl Iterator for Scaled { type Item = i64; fn next(&mut self) -> Option<i64> { self.inner.next().map(|v| v * self.k) } }
#[derive(Clone)] struct Rec { #[allow(dead_code)] id: i64, score: i64 }
struct RecIter { items: Vec<Rec>, at: usize }
impl Iterator for RecIter { type Item = Rec; fn next(&mut self) -> Option<Rec> { if self.at >= self.items.len() { return None } self.at += 1; Some(self.items[self.at - 1].clone()) } }

fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }
fn w_counter() -> i64 { let mut t = 0; for v in (Counter { at: 0, end: 50000000 }) { t += v % 7; } t }
fn w_counter_while() -> i64 { let mut t = 0; let mut i = 0; while i < 50000000 { t += i % 7; i += 1; } t }
fn w_adapter_chain() -> i64 { let mut t = 0; for v in (Scaled { inner: Box::new(Evens { inner: Box::new(Counter { at: 0, end: 50000000 }) }), k: 3 }) { t += v % 11; } t }
fn w_rec_iter() -> i64 { let xs: Vec<Rec> = (0..1000000).map(|i| Rec { id: i, score: i % 13 }).collect(); let mut t = 0; for _ in 0..10 { for v in (RecIter { items: xs.clone(), at: 0 }) { t += v.score; } } t }
fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() { run("w_counter", w_counter); run("w_counter_while", w_counter_while); run("w_adapter_chain", w_adapter_chain); run("w_rec_iter", w_rec_iter); }
