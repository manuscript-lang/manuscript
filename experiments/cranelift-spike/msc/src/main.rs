//! `msc`: a spike compiler for a value-semantics Manuscript subset that emits
//! native code through Cranelift and links the `msrt` runtime.
//!
//! usage: msc <file.ms> -o <exe> [--no-checks] [--no-poll] [--no-inline] [--obj <file.o>]

mod check;
mod codegen;
mod syntax;
mod types;

use std::path::PathBuf;
use std::process::{exit, Command};
use std::time::Instant;

fn main() {
    let mut args = std::env::args().skip(1);
    let (mut input, mut output, mut obj) = (None, None, None);
    let mut opts = codegen::Options { checks: true, poll: true, inline: true };
    while let Some(a) = args.next() {
        match a.as_str() {
            "-o" => output = args.next(),
            "--obj" => obj = args.next(),
            "--no-checks" => opts.checks = false,
            "--no-poll" => opts.poll = false,
            "--no-inline" => opts.inline = false,
            _ => input = Some(a),
        }
    }
    let (Some(input), Some(output)) = (input, output) else {
        eprintln!("usage: msc <file.ms> -o <exe> [--no-checks] [--no-poll] [--no-inline] [--obj <file.o>]");
        exit(2)
    };
    let src = std::fs::read_to_string(&input).unwrap_or_else(|e| fail(&format!("{input}: {e}")));
    let t0 = Instant::now();
    let prog = syntax::parse(&src).unwrap_or_else(|e| fail(&format!("{input}:{e}")));
    let t1 = Instant::now();
    let checked = check::check(&prog).unwrap_or_else(|e| fail(&format!("{input}:{e}")));
    let t2 = Instant::now();
    let object = codegen::compile(&prog, &checked, opts).unwrap_or_else(|e| fail(&e));
    let t3 = Instant::now();
    let obj = obj.map(PathBuf::from).unwrap_or_else(|| PathBuf::from(format!("{output}.o")));
    std::fs::write(&obj, object).unwrap_or_else(|e| fail(&e.to_string()));
    let runtime = std::env::var("MSRT").map(PathBuf::from).unwrap_or_else(|_| {
        std::env::current_exe().unwrap().with_file_name("libmsrt.a")
    });
    let linker = std::env::var("MSC_LINKER").unwrap_or_else(|_| "cc".into());
    let ld = std::env::var("MSC_LD").unwrap_or_else(|_| "lld".into());
    let status = Command::new(&linker)
        .arg(format!("-fuse-ld={ld}"))
        .arg(&obj)
        .arg(&runtime)
        .args(["-o", &output])
        .status()
        .unwrap_or_else(|e| fail(&format!("{linker}: {e}")));
    if !status.success() {
        fail("link failed");
    }
    let t4 = Instant::now();
    let ms = |a: Instant, b: Instant| (b - a).as_secs_f64() * 1000.0;
    eprintln!(
        "msc: parse {:.2}ms check {:.2}ms codegen {:.2}ms link {:.2}ms total {:.2}ms",
        ms(t0, t1),
        ms(t1, t2),
        ms(t2, t3),
        ms(t3, t4),
        ms(t0, t4)
    );
}

fn fail(msg: &str) -> ! {
    eprintln!("msc: {msg}");
    exit(1)
}
