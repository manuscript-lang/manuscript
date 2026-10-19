//! `mirc <file.mir> -o <exe> [--rt <runtime.o|.a>] [--no-checks] [--no-poll] [--opt none|speed] [--dump-clif]`
//!
//! Compiles a MIR text file to a native executable. Without `--rt` the C test
//! runtime used by the backend tests is built and linked.

use ms_clif::{Options, compile};
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let mut args = std::env::args().skip(1);
    let (mut input, mut out, mut rt) = (None, None, None);
    let mut opts = Options::default();
    let mut optimize = true;
    while let Some(a) = args.next() {
        match a.as_str() {
            "-o" => out = args.next().map(PathBuf::from),
            "--rt" => rt = args.next().map(PathBuf::from),
            "--no-checks" => opts.checks = false,
            "--no-poll" => opts.poll = false,
            "--dump-clif" => opts.dump_clif = true,
            "--no-opt" => optimize = false,
            "--opt" => {
                opts.opt_level = match args.next().as_deref() {
                    Some("none") => "none",
                    _ => "speed",
                }
            }
            _ => input = Some(PathBuf::from(a)),
        }
    }
    let (input, out) = (input.expect("input file"), out.expect("-o <exe>"));
    let src = std::fs::read_to_string(&input).expect("read input");
    let mut m = ms_mir::parse::parse_module(&src).unwrap_or_else(|e| panic!("{e}"));
    if let Err(errs) = ms_mir::verify::verify_module(&m) {
        for e in errs {
            eprintln!("{e}");
        }
        std::process::exit(2);
    }
    if optimize {
        ms_mir::opt::optimize(&mut m, ms_mir::opt::Level::Speed, true);
    }
    let obj = compile(&m, &opts).unwrap_or_else(|e| panic!("{e}"));
    let objp = out.with_extension("o");
    std::fs::write(&objp, obj).expect("write object");
    let cc_obj = |name: &str| {
        let p = out.with_file_name(format!("{name}.o"));
        let c = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!("tests/rt/{name}.c"));
        let st = Command::new("cc")
            .args(["-O2", "-c", "-fno-omit-frame-pointer", "-o"])
            .arg(&p)
            .arg(c)
            .status()
            .expect("cc");
        assert!(st.success());
        p
    };
    // The real runtime has no msrt_print_* hooks; the shim supplies them for fixtures.
    let inputs = match rt {
        Some(rt) => vec![cc_obj("printshim"), rt],
        None => vec![cc_obj("testrt")],
    };
    let refs: Vec<&std::path::Path> = inputs.iter().map(|p| p.as_path()).collect();
    ms_clif::link::link_all(&objp, &refs, &out).unwrap_or_else(|e| panic!("{e}"));
}
