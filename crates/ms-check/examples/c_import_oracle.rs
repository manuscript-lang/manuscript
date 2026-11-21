//! Answers import-hint queries the way `ms-check` does, for the C port in
//! `src/compiler/src/check/import_hints.c` to be diffed against (`src/compiler/tests/import-hints-diff.sh`).
//! Each stdin line is `import<TAB>Name`, `typeimport<TAB>Name` or `export<TAB>path<TAB>Name`; each
//! output line is the hint or the diagnostic the checker gives. `gen COUNT SEED` writes random
//! queries from the standard library's own names, misspelled. Temporary tooling for the C rewrite:
//! delete it with the Rust checker.

use ms_check::api::hints::{import_hint, type_import_hint};
use ms_check::{CheckOptions, ImportMap, Session, check_in, load_module};
use ms_syntax::Names;
use std::io::{BufRead, Write};
use std::rc::Rc;
use std::sync::Arc;

fn export_message(session: &Rc<Session>, path: &str, name: &str) -> String {
    let source = format!("import {name} from \"{path}\"\n");
    let file: Arc<str> = Arc::from("main.ms");
    let Ok(ast) = ms_syntax::parser::parse(&file, &source) else {
        return "parse-error".into();
    };
    let syms = Names::global();
    let module = load_module(syms, &ast);
    let program = check_in(
        syms,
        session,
        vec![module],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program
        .diagnostics
        .iter()
        .map(|d| d.message.clone())
        .find(|m| {
            m.starts_with("module does not export") || m.starts_with("unknown standard module")
        })
        .unwrap_or_else(|| "-".into())
}

fn answer(session: &Rc<Session>, line: &str) -> String {
    let f: Vec<&str> = line.split('\t').collect();
    match f[0] {
        "import" => import_hint(session, f[1]),
        "typeimport" => type_import_hint(session, f[1]),
        "export" => export_message(session, f[1], f[2]),
        other => panic!("unknown op {other}"),
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

/// A one-letter slip: drop, swap or double a letter.
fn misspell(rng: &mut Rng, word: &str) -> String {
    let mut chars: Vec<char> = word.chars().collect();
    if chars.len() < 2 {
        return word.to_string();
    }
    let at = rng.below(chars.len() - 1);
    match rng.below(3) {
        0 => {
            chars.remove(at);
        }
        1 => chars.swap(at, at + 1),
        _ => chars.insert(at, chars[at]),
    }
    chars.into_iter().collect()
}

fn parses_as_name(name: &str) -> bool {
    let file: Arc<str> = Arc::from("main.ms");
    ms_syntax::parser::parse(&file, &format!("import {name} from \"x.ms\"\n")).is_ok()
}

fn generate(count: usize, seed: u64) {
    let session = Session::new();
    session.ensure_standard();
    let modules: Vec<String> = session
        .standard_module_names()
        .iter()
        .map(|m| m.to_string())
        .collect();
    let mut names: Vec<String> = Vec::new();
    for m in &modules {
        let syms = Names::global();
        names.extend(
            session
                .standard_exports(m)
                .keys()
                .map(|k| syms.str(*k).to_string()),
        );
    }
    names.sort();
    names.dedup();
    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let name = names[rng.below(names.len())].clone();
        let slip = misspell(&mut rng, &name);
        // A slip can land on a keyword, which is not a name to import.
        let name = if rng.below(3) == 0 && parses_as_name(&slip) {
            slip
        } else {
            name
        };
        let module = modules[rng.below(modules.len())].clone();
        let path = match rng.below(6) {
            0 => module.trim_end_matches(".ms").to_string(),
            1 => misspell(&mut rng, &module),
            2 => format!("@std/{}", module.rsplit('/').next().unwrap_or(&module)),
            3 => "@std/concurrency/flow.ms".to_string(),
            _ => module,
        };
        match rng.below(4) {
            0 => writeln!(out, "import\t{name}").unwrap(),
            1 => writeln!(out, "typeimport\t{name}").unwrap(),
            _ => writeln!(out, "export\t{path}\t{name}").unwrap(),
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("gen") {
        generate(args[2].parse().unwrap(), args[3].parse().unwrap());
        return;
    }
    let session = Session::new();
    session.ensure_standard();
    let stdin = std::io::stdin();
    let out = std::io::stdout();
    let mut out = out.lock();
    for line in stdin.lock().lines() {
        writeln!(out, "{}", answer(&session, &line.unwrap())).unwrap();
    }
}
