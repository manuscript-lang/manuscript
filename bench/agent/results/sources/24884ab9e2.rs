use std::collections::BTreeMap;
use std::io::{self, Read, Write};

struct Record<'a> {
    timestamp: &'a [u8],
    level: &'a [u8],
    method: &'a [u8],
    path: &'a [u8],
    status: u32,
    latency: u64,
}

fn parse_line(line: &[u8]) -> Option<Record<'_>> {
    let fields: Vec<&[u8]> = line.split(|&b| b == b' ').collect();
    if fields.len() != 6 {
        return None;
    }
    let (timestamp, level, method, path, status, latency) =
        (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5]);

    if timestamp.is_empty() {
        return None;
    }
    if !matches!(level, b"DEBUG" | b"INFO" | b"WARN" | b"ERROR") {
        return None;
    }
    if !matches!(method, b"GET" | b"POST" | b"PUT" | b"DELETE") {
        return None;
    }
    if path.is_empty() || path[0] != b'/' {
        return None;
    }
    if status.len() != 3 || !status.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if latency.is_empty() || latency.len() > 9 || !latency.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let status = status.iter().fold(0u32, |acc, &b| acc * 10 + (b - b'0') as u32);
    let latency = latency.iter().fold(0u64, |acc, &b| acc * 10 + (b - b'0') as u64);
    Some(Record { timestamp, level, method, path, status, latency })
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).expect("failed to read stdin");

    let mut valid_count: u64 = 0;
    let mut malformed: u64 = 0;
    let mut level_counts = [0u64; 4]; // DEBUG, INFO, WARN, ERROR
    let mut status_counts = [0u64; 5]; // 2xx, 3xx, 4xx, 5xx, other
    let mut latencies: Vec<u64> = Vec::new();
    // slowest: (latency, method, path, timestamp); strict > keeps the earliest on ties
    let mut slowest: Option<(u64, &[u8], &[u8], &[u8])> = None;
    // path -> (count, total latency)
    let mut paths: BTreeMap<&[u8], (u64, u64)> = BTreeMap::new();

    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|b| b.is_ascii_whitespace()) {
            continue;
        }
        let rec = match parse_line(line) {
            Some(r) => r,
            None => {
                malformed += 1;
                continue;
            }
        };
        valid_count += 1;
        let li = match rec.level {
            b"DEBUG" => 0,
            b"INFO" => 1,
            b"WARN" => 2,
            _ => 3,
        };
        level_counts[li] += 1;
        let si = match rec.status / 100 {
            2 => 0,
            3 => 1,
            4 => 2,
            5 => 3,
            _ => 4,
        };
        status_counts[si] += 1;
        latencies.push(rec.latency);
        match slowest {
            Some((best, ..)) if best >= rec.latency => {}
            _ => slowest = Some((rec.latency, rec.method, rec.path, rec.timestamp)),
        }
        let e = paths.entry(rec.path).or_insert((0, 0));
        e.0 += 1;
        e.1 += rec.latency;
    }

    let mut out = Vec::new();
    let _ = writeln!(out, "valid: {}", valid_count);
    let _ = writeln!(out, "malformed: {}", malformed);
    let _ = writeln!(out, "DEBUG: {}", level_counts[0]);
    let _ = writeln!(out, "INFO: {}", level_counts[1]);
    let _ = writeln!(out, "WARN: {}", level_counts[2]);
    let _ = writeln!(out, "ERROR: {}", level_counts[3]);
    let _ = writeln!(
        out,
        "status: 2xx={} 3xx={} 4xx={} 5xx={} other={}",
        status_counts[0], status_counts[1], status_counts[2], status_counts[3], status_counts[4]
    );

    let p95 = if latencies.is_empty() {
        0
    } else {
        latencies.sort_unstable();
        let n = latencies.len() as u64;
        let rank = ((95 * n + 99) / 100) as usize;
        latencies[rank - 1]
    };
    let _ = writeln!(out, "p95: {}", p95);

    if let Some((lat, method, path, ts)) = slowest {
        let _ = out.write_all(b"slowest: ");
        let _ = write!(out, "{} ", lat);
        let _ = out.write_all(method);
        let _ = out.write_all(b" ");
        let _ = out.write_all(path);
        let _ = out.write_all(b" ");
        let _ = out.write_all(ts);
        let _ = out.write_all(b"\n");
    }

    let _ = writeln!(out, "top:");
    let mut ranked: Vec<(&[u8], u64, u64)> = paths.iter().map(|(p, &(c, t))| (*p, c, t)).collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
    for (path, count, total) in ranked.into_iter().take(3) {
        let _ = out.write_all(path);
        let _ = writeln!(out, " {} avg={}", count, total / count);
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(&out);
    let _ = lock.flush();
}
