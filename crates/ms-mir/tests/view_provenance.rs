// A borrowed value points into its owner: using it after the owner was dropped is invalid MIR.

use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;

fn verdict(body: &str) -> Result<(), String> {
    let src = format!("module \"t\"\nfn @t(%l: move list<str>) -> void export {{\n{body}}}\n");
    let m = parse_module(&src).unwrap();
    verify_module(&m).map_err(|e| format!("{e:?}"))
}

#[test]
fn a_borrow_used_after_its_owner_is_dropped_is_rejected() {
    let err = verdict(
        "b0:\n  %i: int = iconst 0\n  %s: str = list.get %l, %i\n  drop %l\n  %n: int = str.len %s\n  %v: void = void\n  ret %v\n",
    )
    .unwrap_err();
    assert!(err.contains("points into"), "{err}");
}

#[test]
fn a_borrow_used_before_its_owner_is_dropped_is_accepted() {
    verdict(
        "b0:\n  %i: int = iconst 0\n  %s: str = list.get %l, %i\n  %n: int = str.len %s\n  drop %l\n  %v: void = void\n  ret %v\n",
    )
    .unwrap();
}
