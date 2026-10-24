//! `var x = place` and `if var` borrow the place: changes through `x` change the origin, on every
//! exit path, and the ownership rules are enforced in any function that holds such a borrow.

use std::process::Command;

fn run_ms(args: &[&str]) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .output()
        .unwrap();
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.code(), text)
}

fn fixture(name: &str) -> String {
    format!("{}/tests/borrows/{name}", env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn borrows_write_through_on_every_exit() {
    let (status, text) = run_ms(&["run", &fixture("exits_and_paths.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(
        text,
        "[[0, 1, 1, 2], [0]]\n\
         [[0, 100], [0], [0]]\n\
         [[0], [0, 7, 7, 8]]\n\
         [[a, z], [b]]\n\
         [[1, 9], [2]]\n\
         [Box(items: [], name: p), Box(items: [1, 42], name: renamed)]\n\
         [[0, 55], [0], [1]]\n"
    );
}

#[test]
fn if_var_borrows_map_and_list_entries() {
    let (status, text) = run_ms(&["run", &fixture("map_and_list_entries.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(
        text,
        "2 2 [x] [[1, 5], [2], [9]] 15 Optional.some(Counter(count: 15, tags: [t])) [[1, 2], [3, 4]]\n"
    );
}

#[test]
fn touching_the_origin_while_borrowed_is_rejected() {
    let (status, text) = run_ms(&["run", &fixture("rejected_read_origin.ms")]);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("cannot use `rows` while `head`"), "{text}");
    let (status, text) = run_ms(&["run", &fixture("rejected_change_origin.ms")]);
    assert_eq!(status, Some(1), "{text}");
    assert!(
        text.contains("cannot change `m` while `e` borrows it"),
        "{text}"
    );
}

#[test]
fn getter_results_borrow_their_argument() {
    let (status, text) = run_ms(&["run", &fixture("getter_results.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(
        text,
        "[1, 2] [1, 2] 2 [0] [0, 100] [3] [5, 5, 6] 1 3 [1, 2]\n"
    );
}

#[test]
fn touching_the_parent_of_a_getter_borrow_is_rejected() {
    let (status, text) = run_ms(&["run", &fixture("rejected_getter_parent.ms")]);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("cannot use `b.items` while `xs`"), "{text}");
}

#[test]
fn var_of_a_scalar_part_writes_through() {
    let (status, text) = run_ms(&["run", &fixture("scalar_borrows.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(text, "4 Optional.some(2) [11, 2, 3] 104\n");
}

#[test]
fn explicit_optional_defaults_preserve_owned_payloads() {
    for build_type in ["Debug", "Release"] {
        let (status, text) = run_ms(&[
            "run",
            &fixture("optional_defaults.ms"),
            "--build-type",
            build_type,
        ]);
        assert_eq!(status, Some(0), "{text}");
        assert_eq!(
            text,
            "[99] [1]\n\
         [99] [2]\n\
         [99] [3] [3]\n\
         [88] [88] [88] Optional.some([88])\n\
         missing 7\n\
         [1] [2] [3]\n\
         [1] [99] [2] [99] [3] [99] 6\n\
         fallback fallback fallback Optional.some(fallback)\n\
         [4] [5]\n"
        );
    }
}

#[test]
fn standard_library_source_copies_what_it_reads() {
    let (status, text) = run_ms(&["run", &fixture("stdlib_source_copies.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(
        text,
        "a-longer-string-number-6;a-longer-string-number-1;a-longer-string-number-5;\
         a-longer-string-number-2;a-longer-string-number-4;a-longer-string-number-3;\n"
    );
}

#[test]
fn borrow_identities_are_unique_across_the_standard_library() {
    let (status, text) = run_ms(&["run", &fixture("stdlib_binding_ids.ms")]);
    assert_eq!(status, Some(0), "{text}");
    assert_eq!(text, "Optional.some(3) 25 Optional.some(hello!)\n");
}

#[test]
fn looping_or_matching_a_parameter_borrows_it() {
    let (status, text) = run_ms(&["run", &fixture("param_scrutinee.ms")]);
    assert_eq!(status, Some(0), "{text}");
}
