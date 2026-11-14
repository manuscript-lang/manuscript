// Rust control for bench/tools/platform_io.ms: the same small-file, rename, walk, spawn and pipe
// round-trip operations through std only, so a slow platform is blamed on the OS only when this is
// equally slow. Usage: main <files> <program that accepts --version>; it spawns itself with
// --echo for the pipe round trip. Prints ns per operation,
// min of three rounds, in the driver's format.
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::time::Instant;

fn report(name: &str, best_ns: u128, ops: u128) {
    println!("{} {} {} ns/op ({} ops)", std::env::consts::OS, name, best_ns / ops, ops);
}

fn walk(dir: &str) -> usize {
    let mut found = 0;
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        found += 1;
        if entry.file_type().unwrap().is_dir() {
            found += walk(entry.path().to_str().unwrap());
        }
    }
    found
}

// The child of the pipe round trip: echoes every line it reads.
fn echo() {
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    for line in stdin.lock().lines() {
        writeln!(out, "{}", line.unwrap()).unwrap();
        out.flush().unwrap();
    }
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--echo") {
        return echo();
    }
    let mut args = std::env::args().skip(1);
    let n: usize = args.next().map_or(2000, |a| a.parse().unwrap());
    let program = args.next().unwrap();
    let root = std::env::temp_dir().join(format!("platform-io-rust-{}", std::process::id()));
    let root = root.to_str().unwrap().to_string();
    let mut best = [u128::MAX; 4];
    for round in 0..3 {
        let dir = format!("{root}/r{round}");
        fs::create_dir_all(format!("{dir}/sub")).unwrap();
        let t = Instant::now();
        for i in 0..n {
            fs::write(format!("{dir}/f{i}.txt"), format!("file {i}\n")).unwrap();
        }
        best[0] = best[0].min(t.elapsed().as_nanos());
        let t = Instant::now();
        let mut total = 0;
        for i in 0..n {
            total += fs::read(format!("{dir}/f{i}.txt")).unwrap().len();
        }
        assert!(total > 0);
        best[1] = best[1].min(t.elapsed().as_nanos());
        let t = Instant::now();
        for i in 0..n {
            fs::rename(format!("{dir}/f{i}.txt"), format!("{dir}/g{i}.txt")).unwrap();
        }
        best[2] = best[2].min(t.elapsed().as_nanos());
        let t = Instant::now();
        assert!(walk(&root) > 0);
        best[3] = best[3].min(t.elapsed().as_nanos());
    }
    report("write_file", best[0], n as u128);
    report("read_file", best[1], n as u128);
    report("rename", best[2], n as u128);
    report("walk entry", best[3], n as u128);
    fs::remove_dir_all(&root).unwrap();

    let mut spawn = u128::MAX;
    for _ in 0..3 {
        let t = Instant::now();
        for _ in 0..30 {
            Command::new(&program).arg("--version").output().unwrap();
        }
        spawn = spawn.min(t.elapsed().as_nanos());
    }
    report("spawn and wait", spawn, 30);

    {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .arg("--echo")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut input = child.stdin.take().unwrap();
        let mut output = BufReader::new(child.stdout.take().unwrap());
        let mut best = u128::MAX;
        for _ in 0..3 {
            let t = Instant::now();
            let mut line = String::new();
            for _ in 0..300 {
                input.write_all(b"ping\n").unwrap();
                input.flush().unwrap();
                line.clear();
                output.read_line(&mut line).unwrap();
            }
            best = best.min(t.elapsed().as_nanos());
        }
        report("pipe round trip", best, 300);
        child.kill().unwrap();
        let _ = child.wait();
    }
}
