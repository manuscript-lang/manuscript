use std::io::{self, Read, Write};

const BAD: &[u8] = b"error: bad command";

/// Parses a decimal number of 1 to 6 ASCII digits (no sign).
fn parse_num(t: &[u8]) -> Option<u64> {
    if t.is_empty() || t.len() > 6 || !t.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut n: u64 = 0;
    for &b in t {
        n = n * 10 + (b - b'0') as u64;
    }
    Some(n)
}

fn lcs(a: &[u8], b: &[u8]) -> u64 {
    let m = b.len();
    let mut prev = vec![0u32; m + 1];
    let mut cur = vec![0u32; m + 1];
    for &ca in a {
        for j in 1..=m {
            cur[j] = if ca == b[j - 1] {
                prev[j - 1] + 1
            } else {
                prev[j].max(cur[j - 1])
            };
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[m] as u64
}

fn edit(a: &[u8], b: &[u8]) -> u64 {
    let m = b.len();
    let mut prev: Vec<u32> = (0..=m as u32).collect();
    let mut cur = vec![0u32; m + 1];
    for (i, &ca) in a.iter().enumerate() {
        cur[0] = (i + 1) as u32;
        for j in 1..=m {
            let sub = prev[j - 1] + if ca == b[j - 1] { 0 } else { 1 };
            cur[j] = sub.min(prev[j] + 1).min(cur[j - 1] + 1);
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[m] as u64
}

/// 0/1 knapsack. `items` have weight >= 1. Returns the best value with total weight <= cap.
fn knap(cap: u64, items: &[(u64, u64)]) -> u64 {
    // Weights beyond the total weight sum can never be used, so bound the table by it.
    let total_w: u64 = items.iter().map(|&(w, _)| w).sum();
    let c = cap.min(total_w) as usize;
    // dp[x] = best value using a subset of processed items with total weight <= x.
    let mut dp = vec![0u64; c + 1];
    for &(w, v) in items {
        let w = w as usize;
        if w > c {
            continue;
        }
        for x in (w..=c).rev() {
            let cand = dp[x - w] + v;
            if cand > dp[x] {
                dp[x] = cand;
            }
        }
    }
    dp[c]
}

/// Minimum coin count summing exactly to `amount`, or None if impossible.
fn coins(amount: u64, denoms: &[u64]) -> Option<u64> {
    let amount = amount as usize;
    let mut ds: Vec<usize> = denoms
        .iter()
        .map(|&d| d as usize)
        .filter(|&d| d <= amount)
        .collect();
    ds.sort_unstable();
    ds.dedup();
    const INF: u32 = u32::MAX;
    let mut dp = vec![INF; amount + 1];
    dp[0] = 0;
    for x in 1..=amount {
        let mut best = INF;
        for &d in &ds {
            if d > x {
                break;
            }
            let p = dp[x - d];
            if p != INF && p + 1 < best {
                best = p + 1;
            }
        }
        dp[x] = best;
    }
    if dp[amount] == INF {
        None
    } else {
        Some(dp[amount] as u64)
    }
}

fn run_command(line: &[u8]) -> Vec<u8> {
    let tokens: Vec<&[u8]> = line.split(|&b| b == b' ').collect();
    let cmd = tokens[0];
    let args = &tokens[1..];
    match cmd {
        b"lcs" | b"edit" => {
            if args.len() != 2 || args[0].is_empty() || args[1].is_empty() {
                return BAD.to_vec();
            }
            let r = if cmd == b"lcs" {
                lcs(args[0], args[1])
            } else {
                edit(args[0], args[1])
            };
            r.to_string().into_bytes()
        }
        b"knap" => {
            if args.is_empty() {
                return BAD.to_vec();
            }
            let cap = match parse_num(args[0]) {
                Some(c) => c,
                None => return BAD.to_vec(),
            };
            let mut items = Vec::with_capacity(args.len() - 1);
            for &it in &args[1..] {
                let parts: Vec<&[u8]> = it.split(|&b| b == b':').collect();
                if parts.len() != 2 {
                    return BAD.to_vec();
                }
                let (w, v) = match (parse_num(parts[0]), parse_num(parts[1])) {
                    (Some(w), Some(v)) if w >= 1 => (w, v),
                    _ => return BAD.to_vec(),
                };
                items.push((w, v));
            }
            knap(cap, &items).to_string().into_bytes()
        }
        b"coins" => {
            if args.len() < 2 {
                return BAD.to_vec();
            }
            let amount = match parse_num(args[0]) {
                Some(a) => a,
                None => return BAD.to_vec(),
            };
            let mut denoms = Vec::with_capacity(args.len() - 1);
            for &t in &args[1..] {
                match parse_num(t) {
                    Some(c) if c >= 1 => denoms.push(c),
                    _ => return BAD.to_vec(),
                }
            }
            match coins(amount, &denoms) {
                Some(n) => n.to_string().into_bytes(),
                None => b"impossible".to_vec(),
            }
        }
        _ => BAD.to_vec(),
    }
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).expect("read stdin");

    let mut out: Vec<u8> = Vec::new();
    for raw in input.split(|&b| b == b'\n') {
        // Blank means empty or only spaces: produces no output line.
        if raw.iter().all(|&b| b == b' ') {
            continue;
        }
        out.extend_from_slice(&run_command(raw));
        out.push(b'\n');
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(&out).expect("write stdout");
    lock.flush().expect("flush stdout");
}
