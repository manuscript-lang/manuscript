//! `msl`: developer driver for the native pipeline.

use std::path::Path;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let h = std::thread::Builder::new()
        .stack_size(512 << 20)
        .spawn(move || run(args))
        .expect("spawn");
    std::process::exit(h.join().unwrap_or(2));
}

fn run(args: Vec<String>) -> i32 {
    match args.first().map(String::as_str) {
        Some("dump") => {
            let loaded = ms_lower::load::load(Path::new(&args[1]));
            for d in &loaded.diagnostics {
                eprintln!("{d}");
            }
            if let Some(p) = &loaded.program {
                print!("{}", ms_lower::dump::dump(p));
            }
            0
        }
        Some("test") => {
            let mut opts = ms_lower::pipeline::BuildOptions::default();
            let mut file = None;
            let mut json = false;
            for a in &args[1..] {
                match a.as_str() {
                    "--json" => json = true,
                    "--no-opt" => opts.no_opt = true,
                    "--dump-mir" => opts.dump_mir = true,
                    _ if file.is_none() => file = Some(a.clone()),
                    _ => {}
                }
            }
            let Some(file) = file else {
                eprintln!("usage: msl test FILE [--json]");
                return 2;
            };
            match ms_lower::pipeline::test(Path::new(&file), json, &opts) {
                Ok(code) => code,
                Err(ms_lower::pipeline::BuildError::Diagnostics) => 1,
                Err(ms_lower::pipeline::BuildError::Failed(m)) => {
                    eprintln!("msl: {m}");
                    70
                }
            }
        }
        Some("run") | Some("build") => {
            let mut opts = ms_lower::pipeline::BuildOptions::default();
            let mut file = None;
            let mut rest = Vec::new();
            let mut out = None;
            let mut it = args[1..].iter();
            while let Some(a) = it.next() {
                match a.as_str() {
                    "--no-opt" => opts.no_opt = true,
                    "--dump-mir" => opts.dump_mir = true,
                    "--inline" => opts.inline = true,
                    "-o" => out = it.next().cloned(),
                    "--" => {
                        rest.extend(it.by_ref().cloned());
                    }
                    _ if file.is_none() => file = Some(a.clone()),
                    _ => rest.push(a.clone()),
                }
            }
            let Some(file) = file else {
                eprintln!("usage: msl run|build FILE");
                return 2;
            };
            let r = if args[0] == "run" {
                ms_lower::pipeline::run(Path::new(&file), &rest, &opts)
            } else {
                let out = out.unwrap_or_else(|| "program".to_string());
                ms_lower::pipeline::build(Path::new(&file), Path::new(&out), &opts).map(|()| 0)
            };
            match r {
                Ok(code) => code,
                Err(ms_lower::pipeline::BuildError::Diagnostics) => 1,
                Err(ms_lower::pipeline::BuildError::Failed(m)) => {
                    eprintln!("msl: {m}");
                    70
                }
            }
        }
        _ => {
            eprintln!("usage: msl dump|run|build FILE");
            2
        }
    }
}
