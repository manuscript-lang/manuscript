use std::collections::BTreeMap;
use std::time::Instant;

enum Instr { Load(usize, i64), AddR(usize, usize), #[allow(dead_code)] SubR(usize, usize), MulR(usize, usize), Jnz(usize, usize), Dec(usize), Xor(usize, usize), Halt }
#[derive(Clone, Copy)]
enum State { Idle, Running(i64), Blocked(i64), Done }
#[derive(Clone)]
struct Shape2 { w: i64, h: i64 }
trait Sized_ { fn area(&self) -> i64; }
impl Sized_ for Shape2 { fn area(&self) -> i64 { self.w * self.h } }
#[derive(Clone)]
struct Inventory { #[allow(dead_code)] name: String, counts: Vec<i64>, tags: Vec<String> }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn stop(name: &str, t0: Instant, chk: i64) { println!("{} {} {}", name, t0.elapsed().as_micros(), chk); }

fn y_vm() -> i64 {
    let prog = vec![Instr::Load(0, 3000000), Instr::Load(1, 0), Instr::AddR(1, 0), Instr::Load(2, 7), Instr::MulR(1, 2), Instr::Load(3, 1000003), Instr::Xor(1, 3), Instr::Dec(0), Instr::Jnz(0, 2), Instr::Halt];
    let mut regs = vec![0i64; 4]; let mut pc = 0usize; let mut steps = 0i64;
    loop {
        steps += 1;
        match &prog[pc] {
            Instr::Load(r, v) => { regs[*r] = *v; pc += 1 }
            Instr::AddR(a, b) => { regs[*a] = (regs[*a] + regs[*b]) % 1000000007; pc += 1 }
            Instr::SubR(a, b) => { regs[*a] = regs[*a] - regs[*b]; pc += 1 }
            Instr::MulR(a, b) => { regs[*a] = (regs[*a] * regs[*b]) % 1000000007; pc += 1 }
            Instr::Jnz(r, t) => { if regs[*r] != 0 { pc = *t } else { pc += 1 } }
            Instr::Dec(r) => { regs[*r] -= 1; pc += 1 }
            Instr::Xor(a, b) => { regs[*a] = (regs[*a] + regs[*b]) % 1000000007; pc += 1 }
            Instr::Halt => break,
        }
    }
    regs[1] + steps
}
fn y_state_machine() -> i64 { let mut s = State::Idle; let mut t = 0; for i in 0..20000000i64 { match s { State::Idle => s = State::Running(0), State::Running(k) => { if k > 5 { s = State::Blocked(i % 7) } else { s = State::Running(k + 1) } } State::Blocked(on) => { t += on; s = if i % 3 == 0 { State::Done } else { State::Blocked(on + 1) } } State::Done => { t += 1; s = State::Idle } } } t }
fn cmd_code(s: &str) -> i64 { match s { "push" => 1, "pop" => 2, "add" => 3, "sub" => 4, "dup" => 5, "swap" => 6, "jump" => 7, _ => 0 } }
fn y_match_string() -> i64 { let words = ["push", "pop", "add", "sub", "dup", "swap", "jump", "nop"]; let mut t = 0; for i in 0..10000000usize { t += cmd_code(words[i % 8]); } t }
fn y_matmul() -> i64 { let n = 200usize; let a: Vec<Vec<f64>> = (0..n).map(|i| (0..n).map(|j| (i + j) as f64 * 0.5).collect()).collect(); let b: Vec<Vec<f64>> = (0..n).map(|i| (0..n).map(|j| (i as i64 - j as i64) as f64 * 0.25).collect()).collect(); let mut c: Vec<Vec<f64>> = Vec::new(); for i in 0..n { let mut rc = Vec::new(); for j in 0..n { let mut s = 0.0; for k in 0..n { s += a[i][k] * b[k][j]; } rc.push(s); } c.push(rc); } c[17][33] as i64 + c[199][199] as i64 }
fn y_sieve() -> i64 { let n = 20000000usize; let mut sieve = vec![true; n + 1]; let mut i = 2; while i * i <= n { if sieve[i] { let mut j = i * i; while j <= n { sieve[j] = false; j += i; } } i += 1; } let mut c = 0; for k in 2..n + 1 { if sieve[k] { c += 1 } } c }
fn y_sorted_map() -> i64 { let mut m: BTreeMap<i64, i64> = BTreeMap::new(); let mut x = 1; for i in 0..200000 { x = lcg(x); m.insert(x % 1000000, i); } let mut t = 0; for i in 0..200000i64 { t += m.get(&(i * 5)).copied().unwrap_or(0); } t + m.len() as i64 }
fn total_area<T: Sized_>(xs: &[T]) -> i64 { let mut t = 0; for v in xs { t += v.area(); } t }
fn y_generic_bound() -> i64 { let xs: Vec<Shape2> = (0..1000000).map(|i| Shape2 { w: i % 10, h: i % 7 }).collect(); let mut t = 0; for _ in 0..20 { t += total_area(&xs); } t }
fn y_clone_records() -> i64 { let base = Inventory { name: "widget".into(), counts: vec![1, 2, 3, 4, 5, 6, 7, 8], tags: vec!["a".into(), "b".into(), "c".into()] }; let mut t = 0; for i in 0..1000000i64 { let mut c = base.clone(); c.counts[(i % 8) as usize] += i; t += c.counts[(i % 8) as usize] + c.tags.len() as i64; } t }
fn y_optional_ints() -> i64 { let xs: Vec<Option<i64>> = (0..2000000i64).map(|i| if i % 3 == 0 { None } else { Some(i) }).collect(); let mut t = 0; for _ in 0..10 { for v in &xs { if let Some(x) = v { t += x } } } t }
fn y_stats() -> i64 { let mut x = 1; let xs: Vec<f64> = (0..2000000).map(|_| { x = lcg(x); (x % 10000) as f64 / 100.0 }).collect(); let mut t = 0.0; for _ in 0..10 { let mean = xs.iter().sum::<f64>() / xs.len() as f64; let v = xs.iter().fold(0.0, |acc, e| acc + (e - mean) * (e - mean)) / xs.len() as f64; t += v.sqrt(); } t as i64 }

fn run(name: &str, f: fn() -> i64) { let t0 = Instant::now(); let c = f(); stop(name, t0, c); }
fn main() { run("y_vm", y_vm); run("y_state_machine", y_state_machine); run("y_match_string", y_match_string); run("y_matmul", y_matmul); run("y_sieve", y_sieve); run("y_sorted_map", y_sorted_map); run("y_generic_bound", y_generic_bound); run("y_clone_records", y_clone_records); run("y_optional_ints", y_optional_ints); run("y_stats", y_stats); }
