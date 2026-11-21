//! Reads the fault families and exit statuses from `runtime/include/ms_rt/fault.h`, the one
//! place that names them, and writes the Rust constants and `FaultKind` the CLI and the code
//! generator use. The C header is the source: nothing here repeats a number.
use std::fmt::Write as _;
use std::path::Path;

const HEADER: &str = "../../runtime/include/ms_rt/fault.h";

fn main() {
    println!("cargo:rerun-if-changed={HEADER}");
    let text = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join(HEADER))
        .expect("read runtime/include/ms_rt/fault.h");
    let kinds = entries(&text, "MS_FAULT_KIND_");
    let exits = entries(&text, "MS_EXIT_");
    assert!(
        !kinds.is_empty() && !exits.is_empty(),
        "no fault kinds or exit statuses found in {HEADER}"
    );

    let mut out = String::new();
    for (name, value) in &exits {
        writeln!(out, "pub const EXIT_{name}: i32 = {value};").unwrap();
    }
    out.push_str(
        "\n/// The family of a fault, chosen by the runtime entry point that raised it.\n",
    );
    out.push_str(
        "#[repr(u8)]\n#[derive(Clone, Copy, Debug, PartialEq, Eq)]\npub enum FaultKind {\n",
    );
    for (name, value) in &kinds {
        writeln!(out, "    {} = {value},", camel(name)).unwrap();
    }
    out.push_str("}\n\nimpl FaultKind {\n");
    out.push_str("    /// The kind with this code; any other code is [`FaultKind::Fault`].\n");
    out.push_str("    pub fn from_code(code: u8) -> FaultKind {\n        match code {\n");
    for (name, value) in kinds.iter().filter(|(_, value)| *value != 0) {
        writeln!(out, "            {value} => FaultKind::{},", camel(name)).unwrap();
    }
    out.push_str("            _ => FaultKind::Fault,\n        }\n    }\n\n");
    out.push_str("    /// The stable name the JSON reports use.\n");
    out.push_str("    pub fn name(self) -> &'static str {\n        match self {\n");
    for (name, _) in &kinds {
        writeln!(
            out,
            "            FaultKind::{} => \"{}\",",
            camel(name),
            name.to_lowercase()
        )
        .unwrap();
    }
    out.push_str("        }\n    }\n}\n");
    let dir = std::env::var("OUT_DIR").expect("OUT_DIR");
    std::fs::write(Path::new(&dir).join("fault_header.rs"), out).expect("write fault_header.rs");
}

/// `(NAME, value)` for every `PREFIXNAME = value` line of the header, prefix removed.
fn entries(text: &str, prefix: &str) -> Vec<(String, u32)> {
    text.lines()
        .filter_map(|line| {
            let rest = line.trim().strip_prefix(prefix)?;
            let (name, tail) = rest.split_once('=')?;
            let digits: String = tail
                .trim()
                .chars()
                .take_while(char::is_ascii_digit)
                .collect();
            Some((name.trim().to_string(), digits.parse().ok()?))
        })
        .collect()
}

/// `DIVISION_BY_ZERO` as `DivisionByZero`.
fn camel(name: &str) -> String {
    name.split('_')
        .map(|word| {
            let mut chars = word.chars();
            chars.next().map_or_else(String::new, |first| {
                first.to_string() + &chars.as_str().to_lowercase()
            })
        })
        .collect()
}
