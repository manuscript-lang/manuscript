use std::fs;
use std::path::{Path, PathBuf};

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            collect(&path, out);
        } else {
            out.push(path);
        }
    }
}

#[derive(Default, Clone, Copy)]
struct Stats {
    lines: u64,
    latency: u64,
    c: [u64; 4],
}

fn summarize(path: &Path) -> Stats {
    let text = fs::read_to_string(path).unwrap();
    let mut s = Stats::default();
    for line in text.split('\n').filter(|l| !l.is_empty()) {
        let f: Vec<&str> = line.split(' ').collect();
        s.lines += 1;
        s.latency += f[5].parse::<u64>().unwrap_or(0);
        let c = (f[4].as_bytes()[0] - b'2').min(3) as usize;
        s.c[c] += 1;
    }
    s
}

fn main() {
    let root = std::env::args().nth(1).unwrap();
    let mut files = Vec::new();
    collect(Path::new(&root), &mut files);
    const WORKERS: usize = 4;
    let parts: Vec<Stats> = std::thread::scope(|scope| {
        let files = &files;
        let handles: Vec<_> = (0..WORKERS)
            .map(|w| {
                scope.spawn(move || {
                    let mut t = Stats::default();
                    for p in files.iter().skip(w).step_by(WORKERS) {
                        let s = summarize(p);
                        t.lines += s.lines;
                        t.latency += s.latency;
                        for i in 0..4 {
                            t.c[i] += s.c[i];
                        }
                    }
                    t
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    let mut t = Stats::default();
    for s in parts {
        t.lines += s.lines;
        t.latency += s.latency;
        for i in 0..4 {
            t.c[i] += s.c[i];
        }
    }
    println!("files: {}", files.len());
    println!("lines: {}", t.lines);
    println!("status: 2xx={} 3xx={} 4xx={} 5xx={}", t.c[0], t.c[1], t.c[2], t.c[3]);
    println!("latency: {}", t.latency);
}
