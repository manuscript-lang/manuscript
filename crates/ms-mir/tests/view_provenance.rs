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

fn map_verdict(body: &str) -> Result<(), String> {
    let src = format!(
        "module \"t\"\nextern @msrt_map_get_ptr(Map<str, str>, ptr, ptr, ptr) -> ptr\nfn @t(%m: move Map<str, str>) -> void export {{\nb0:\n  %k: str = str \"a\"\n  %kd: ptr = typedesc str\n  %vd: ptr = typedesc str\n  %ks: ptr = slot str\n  store %ks, %k\n  %p: ptr = call.rt @msrt_map_get_ptr (%m, %kd, %vd, %ks)\n  %v: str = load str %p\n{body}}}\n"
    );
    let m = parse_module(&src).unwrap();
    verify_module(&m).map_err(|e| format!("{e:?}"))
}

#[test]
fn a_map_entry_used_after_its_map_is_dropped_is_rejected() {
    let err = map_verdict("  drop %m\n  %n: int = str.len %v\n  %u: void = void\n  ret %u\n")
        .unwrap_err();
    assert!(err.contains("points into"), "{err}");
}

#[test]
fn a_map_entry_used_before_its_map_is_dropped_is_accepted() {
    map_verdict("  %n: int = str.len %v\n  drop %m\n  %u: void = void\n  ret %u\n").unwrap();
}

fn edge_verdict(body: &str) -> Result<(), String> {
    let src = format!(
        "module \"t\"\nfn @t(%l: move str) -> void export {{\nb0:\n{body}b1(%p: move str):\n  drop %p\n  %v: void = void\n  ret %v\n}}\n"
    );
    let m = parse_module(&src).unwrap();
    verify_module(&m).map_err(|e| format!("{e:?}"))
}

#[test]
fn an_owned_value_passed_as_a_block_argument_after_its_drop_is_rejected() {
    edge_verdict("  drop %l\n  br b1(%l)\n").unwrap_err();
}

#[test]
fn an_owned_value_passed_as_a_block_argument_is_accepted() {
    edge_verdict("  br b1(%l)\n").unwrap();
}

fn borrowed_edge_verdict(drop_first: bool) -> Result<(), String> {
    let (before, after) = if drop_first {
        ("  drop %l\n", "")
    } else {
        ("", "  drop %l\n")
    };
    let src = format!(
        "module \"t\"\nfn @t(%l: move list<str>) -> void export {{\nb0:\n  %i: int = iconst 0\n  %s: str = list.get %l, %i\n{before}  br b1(%s)\nb1(%p: str):\n  %n: int = str.len %p\n{after}  %v: void = void\n  ret %v\n}}\n"
    );
    let m = parse_module(&src).unwrap();
    verify_module(&m).map_err(|e| format!("{e:?}"))
}

#[test]
fn a_borrow_passed_as_a_block_argument_after_its_owner_is_dropped_is_rejected() {
    borrowed_edge_verdict(true).unwrap_err();
}

#[test]
fn a_borrow_passed_as_a_block_argument_before_its_owner_is_dropped_is_accepted() {
    borrowed_edge_verdict(false).unwrap();
}
