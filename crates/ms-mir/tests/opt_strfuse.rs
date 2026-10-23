use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const CHAIN: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str
extern @msrt_string_empty() -> str
entry @main

fn @join(%0: str, %1: str, %2: str, %3: str) -> str inline(never) {
b0:
  %4: str = call.rt @msrt_string_concat (%0, %1)
  %5: str = call.rt @msrt_string_concat (%4, %2)
  drop %4
  %6: str = call.rt @msrt_string_concat (%5, %3)
  drop %5
  ret %6
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %1: str = call.rt @msrt_string_empty ()
  %2: str = call.rt @msrt_string_empty ()
  %3: str = call.rt @msrt_string_empty ()
  %4: str = call @join (%0, %1, %2, %3)
  drop %4
  drop %3
  drop %2
  drop %1
  drop %0
  %5: int = iconst 0
  ret %5
}
"#;

/// A left-nested chain of concatenations is one allocation.
#[test]
fn concat_chain_becomes_one_call() {
    let mut m = parse_module(CHAIN).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    verify_module(&m).expect("verify after");
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_string_concat4").count(),
        1,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_concat (").count(),
        0,
        "{text}"
    );
    assert_eq!(text.matches("drop").count(), 5, "{text}");
}
