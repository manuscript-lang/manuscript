//! Deep nesting parses in linear time and the depth limit is enforced.
use ms_std_html::{Limits, parse};
use std::time::{Duration, Instant};

#[test]
fn deep_nesting_is_linear_and_limited() {
    let deep = "<div>".repeat(200_000);
    let start = Instant::now();
    let unlimited = Limits {
        max_bytes: None,
        max_depth: None,
        max_nodes: None,
    };
    assert!(parse(&deep, unlimited).is_ok());
    assert!(parse(&deep, Limits::DEFAULT).is_err());
    let list = "<ul><li>".repeat(50_000);
    assert!(parse(&list, unlimited).is_ok());
    // Quadratic parsing takes minutes at this size; linear takes well under a second.
    assert!(start.elapsed() < Duration::from_secs(20));
    assert!(parse(&"<div>".repeat(100), Limits::DEFAULT).is_ok());
}
