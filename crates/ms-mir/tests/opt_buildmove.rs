//! Tests for the `buildmove` pass: `build()` on a builder that is not used again moves its bytes.

use ms_mir::interp::Interp;
use ms_mir::ir::Module;
use ms_mir::opt::buildmove;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

fn parse(src: &str) -> Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

fn exec(m: &Module) -> Result<i64, String> {
    Interp::new(m).run_entry().map_err(|f| f.to_string())
}

fn rewrite(src: &str) -> (Module, bool) {
    let before = parse(src);
    let mut after = before.clone();
    let changed = buildmove::run(&mut after);
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}\n{}", print_module(&after)));
    assert_eq!(exec(&after), exec(&before), "{}", print_module(&after));
    (after, changed)
}

#[test]
fn last_build_moves_the_buffer() {
    let (m, changed) = rewrite(include_str!("fixtures-opt/buildmove_last_use.mir"));
    let text = print_module(&m);
    assert!(changed, "{text}");
    assert!(!text.contains("copy %"), "{text}");
}

#[test]
fn an_earlier_build_of_a_builder_built_again_keeps_its_copy() {
    let src = include_str!("fixtures-opt/buildmove_last_use.mir").replace(
        "  %36: int = call.rt @msrt_string_byte_length (%35)",
        "  %98: bytes = load bytes %29\n  %99: bytes = copy %98\n  drop %99\n  %36: int = call.rt @msrt_string_byte_length (%35)",
    );
    let (m, changed) = rewrite(&src);
    let text = print_module(&m);
    assert!(changed, "{text}");
    assert_eq!(text.matches("copy %").count(), 1, "{text}");
}
