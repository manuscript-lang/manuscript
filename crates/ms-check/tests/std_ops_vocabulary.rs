//! The discarding-mutator names (`api::ownership::discards_entries`) are methods the `@std`
//! collection declarations actually hold as `var fn`, so a rename there cannot leave a stale
//! name behind in the ownership walk or in lowering.

use ms_check::api::ownership::discards_entries;

const COLLECTIONS: &str = include_str!("../../../stdlib/collections/collections.ms");

fn declares_mutator(name: &str) -> bool {
    COLLECTIONS
        .lines()
        .any(|l| l.trim_start().starts_with(&format!("var fn {name}(")))
}

#[test]
fn every_discarding_name_is_a_declared_mutator() {
    for name in ["set", "add", "remove", "clear", "splice"] {
        assert!(discards_entries(name), "{name} should discard");
        assert!(
            declares_mutator(name),
            "`{name}` is listed as discarding but collections.ms declares no `var fn {name}`"
        );
    }
}

#[test]
fn mutators_that_hand_an_entry_out_or_keep_it_do_not_discard() {
    for name in ["append", "insert", "prepend", "pop", "swap", "replace"] {
        assert!(declares_mutator(name), "`{name}` is no longer declared");
        assert!(
            !discards_entries(name),
            "{name} hands its entry out or keeps it"
        );
    }
}
