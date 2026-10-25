use ms_mir::ir::Module;
use std::time::{Duration, Instant};

#[test]
fn interning_the_same_string_returns_the_same_id() {
    let mut m = Module::new("t");
    let a = m.add_string("a");
    let b = m.add_string("b");
    assert_eq!(m.add_string("a"), a);
    assert_eq!(m.add_string("b"), b);
    assert_eq!((a.index(), b.index()), (0, 1));
    assert_eq!(m.strings, ["a", "b"]);
}

#[test]
fn interning_many_distinct_strings_is_linear() {
    let mut m = Module::new("t");
    let start = Instant::now();
    for i in 0..200_000 {
        assert_eq!(m.add_string(&format!("literal {i}")).index(), i);
    }
    assert_eq!(m.add_string("literal 0").index(), 0);
    assert!(start.elapsed() < Duration::from_secs(5));
}
