use std::io::{self, Read, Write};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Eq(usize),
    Del(usize),
    Ins(usize),
}

/// Returns line `k` of the input (without its terminator; a trailing '\r' is dropped).
/// Missing lines (e.g. an empty final line without a terminator) read as empty.
fn get_line<'a>(pieces: &[&'a [u8]], k: usize) -> &'a [u8] {
    match pieces.get(k) {
        Some(p) => {
            if p.last() == Some(&b'\r') {
                &p[..p.len() - 1]
            } else {
                p
            }
        }
        None => &[],
    }
}

fn range_str(start: usize, len: usize) -> String {
    if len == 1 {
        format!("{}", start)
    } else {
        format!("{},{}", start, len)
    }
}

fn main() {
    let mut data = Vec::new();
    io::stdin().read_to_end(&mut data).unwrap();
    let pieces: Vec<&[u8]> = data.split(|&c| c == b'\n').collect();

    let header = String::from_utf8_lossy(get_line(&pieces, 0)).to_string();
    let toks: Vec<&str> = header.split_whitespace().collect();
    let name_a = toks.first().copied().unwrap_or("");
    let name_b = toks.get(1).copied().unwrap_or("");
    let ctx: usize = toks.get(2).and_then(|t| t.parse().ok()).unwrap_or(0);
    let n: usize = toks.get(3).and_then(|t| t.parse().ok()).unwrap_or(0);
    let m: usize = toks.get(4).and_then(|t| t.parse().ok()).unwrap_or(0);

    let a: Vec<&[u8]> = (0..n).map(|k| get_line(&pieces, 1 + k)).collect();
    let b: Vec<&[u8]> = (0..m).map(|k| get_line(&pieces, 1 + n + k)).collect();

    // L[i][j] = LCS length of a[i..] and b[j..], flattened with width m + 1.
    let w = m + 1;
    let mut lcs = vec![0u32; (n + 1) * w];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            lcs[i * w + j] = if a[i] == b[j] {
                lcs[(i + 1) * w + j + 1] + 1
            } else {
                lcs[(i + 1) * w + j].max(lcs[i * w + j + 1])
            };
        }
    }
    let l = |i: usize, j: usize| lcs[i * w + j];

    // Build the edit script exactly as specified.
    let mut ops: Vec<Op> = Vec::with_capacity(n + m);
    let (mut i, mut j) = (0usize, 0usize);
    loop {
        if i == n && j == m {
            break;
        }
        if i < n && j < m && a[i] == b[j] {
            ops.push(Op::Eq(i));
            i += 1;
            j += 1;
        } else if j == m || (i < n && l(i + 1, j) >= l(i, j + 1)) {
            ops.push(Op::Del(i));
            i += 1;
        } else {
            ops.push(Op::Ins(j));
            j += 1;
        }
    }

    let changes: Vec<usize> = (0..ops.len())
        .filter(|&k| !matches!(ops[k], Op::Eq(_)))
        .collect();
    if changes.is_empty() {
        return;
    }

    // Group changes into hunks as script index ranges [start, end).
    let mut ranges: Vec<(usize, usize)> = Vec::new();
    let mut first = changes[0];
    let mut last = changes[0];
    for &ch in &changes[1..] {
        let gap = ch - last - 1;
        if gap <= 2 * ctx {
            last = ch;
        } else {
            ranges.push((first, last));
            first = ch;
            last = ch;
        }
    }
    ranges.push((first, last));

    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(format!("--- {}\n+++ {}\n", name_a, name_b).as_bytes());

    for &(first, last) in &ranges {
        // Add up to `ctx` unchanged lines before and after the changes.
        let mut s = first;
        while s > 0 && first - s < ctx && matches!(ops[s - 1], Op::Eq(_)) {
            s -= 1;
        }
        let mut e = last + 1;
        while e < ops.len() && e - (last + 1) < ctx && matches!(ops[e], Op::Eq(_)) {
            e += 1;
        }

        // Line counts before the hunk in each file.
        let mut sa_before = 0usize;
        let mut sb_before = 0usize;
        for op in &ops[..s] {
            match op {
                Op::Eq(_) => {
                    sa_before += 1;
                    sb_before += 1;
                }
                Op::Del(_) => sa_before += 1,
                Op::Ins(_) => sb_before += 1,
            }
        }
        let mut la = 0usize;
        let mut lb = 0usize;
        for op in &ops[s..e] {
            match op {
                Op::Eq(_) => {
                    la += 1;
                    lb += 1;
                }
                Op::Del(_) => la += 1,
                Op::Ins(_) => lb += 1,
            }
        }
        let sa = sa_before + if la > 0 { 1 } else { 0 };
        let sb = sb_before + if lb > 0 { 1 } else { 0 };

        out.extend_from_slice(
            format!(
                "@@ -{} +{} @@\n",
                range_str(sa, la),
                range_str(sb, lb)
            )
            .as_bytes(),
        );

        for op in &ops[s..e] {
            match *op {
                Op::Eq(x) => {
                    out.push(b' ');
                    out.extend_from_slice(a[x]);
                }
                Op::Del(x) => {
                    out.push(b'-');
                    out.extend_from_slice(a[x]);
                }
                Op::Ins(y) => {
                    out.push(b'+');
                    out.extend_from_slice(b[y]);
                }
            }
            out.push(b'\n');
        }
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(&out).unwrap();
    lock.flush().unwrap();
}
