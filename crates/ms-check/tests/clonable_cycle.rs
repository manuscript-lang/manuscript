//! A self-referential record passed where `Clonable` is required must not recurse forever.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

#[test]
fn self_referential_record_meets_clonable_bound() {
    // `Map.get_or` needs `Node: Clonable`; checking that bound re-enters the `Clonable` query for
    // `List[Node]` through `List.clone`'s own bound, which must see the query in progress.
    let source = "type Node:\n    args: List[Node] = []\n\nexport fn main() Int:\n    let m = Map[Int, Node]()\n    return m.get_or(1, Node()).args.length()\n";
    // A small stack turns the old unbounded recursion into a prompt failure.
    let diagnostics = std::thread::Builder::new()
        .stack_size(16 << 20)
        .spawn(move || {
            let file: Arc<str> = Arc::from("cycle.ms");
            let module = ms_syntax::parser::parse(&file, source).expect("parses");
            ms_check::check(
                vec![ms_check::load_module(&module)],
                ImportMap::default(),
                CheckOptions::default(),
            )
            .diagnostics
            .len()
        })
        .unwrap()
        .join()
        .expect("checker overflowed its stack");
    assert_eq!(diagnostics, 0);
}
