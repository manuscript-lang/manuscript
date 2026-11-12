// Tests for the rules in tools/repo_check.ms; `ms test tools/repo_check_test.ms`.
import (
	expect_contains, expect_equal from "@std/test/test.ms",

	allowed_to_name_editor,
	contains_word,
	extern_names,
	layering_violation,
	normal_dependencies,
	path_names,
	trigger_issues,
	unsafe_allowed,
	unsafe_use,
	uses_thread_unsafe from "./repo_check.ms",
)

GOOD := "name: x\n\non:\n  push:\n    branches: [main]\n  pull_request:\n  merge_group:\n    types: [checks_requested]\n\njobs:\n  a:\n    paths: x\n"

test "required workflow triggers are accepted":
	trigger_issues("w.yml", GOOD) | expect_equal(expected: [])?

test "path filters on pull_request are rejected":
	filtered := GOOD.replace("  pull_request:\n", "  pull_request:\n    paths: [a]\n")
	issues := trigger_issues("w.yml", filtered)
	issues.length() | expect_equal(expected: 1)?
	issues.get(0, "") | expect_contains(expected: "without path filters")?

test "a missing merge queue trigger is rejected":
	queueless := GOOD.replace("  merge_group:\n    types: [checks_requested]\n", "")
	issues := trigger_issues("w.yml", queueless)
	issues.get(0, "") | expect_contains(expected: "merge_group")?

test "benchmark allocators have exact unsafe exceptions":
	unsafe_allowed("bench/perf/binding-flags/main.rs") | expect_equal(expected: true)?
	(
		unsafe_allowed("bench/perf/binding-flags/storage.rs") | expect_equal(
			expected: true
		)?
	)
	unsafe_allowed("bench/perf/other/main.rs") | expect_equal(expected: false)?
	unsafe_allowed("bench/perf/binding-flags/other.rs") | expect_equal(expected: false)?
	(
		unsafe_allowed(
			"bench/perf/binding-flags/main.rs.extra.rs"
		) | expect_equal(expected: false)?
	)
	unsafe_allowed("crates/ms-rt/src/lib.rs") | expect_equal(expected: true)?
	unsafe_allowed("crates/ms-lower/src/lib.rs") | expect_equal(expected: false)?

test "unsafe code is found and prose is not":
	// Spelled apart so this file does not match itself.
	kw := "uns" + "afe"
	unsafe_use("fn f() \{ {kw} \{ g() \} \}").is_some() | expect_equal(expected: true)?
	unsafe_use("{kw} extern \"C\" \{\}").is_some() | expect_equal(expected: true)?
	unsafe_use("// this is {kw} to call").is_some() | expect_equal(expected: false)?
	unsafe_use("let not_{kw} = 1;").is_some() | expect_equal(expected: false)?

test "thread-affine types are found in code, not comments":
	uses_thread_unsafe("let x = Rc::new(1);") | expect_equal(expected: true)?
	uses_thread_unsafe("let x: RefCell<i32>;") | expect_equal(expected: true)?
	(
		uses_thread_unsafe(
			"let x = Arc::new(1); // Rc is slower"
		) | expect_equal(expected: false)?
	)
	uses_thread_unsafe("let src = 1;") | expect_equal(expected: false)?

test "extern declarations are found by name":
	text := "export extern fn a_b(x: Int) Int\nextern fn c[T](y: T) T\n// extern fn skipped\n"
	extern_names(text) | expect_equal(expected: ["a_b", "c"])?

test "names match whole words only":
	contains_word("import a, b_c from x", "b_c") | expect_equal(expected: true)?
	contains_word("import ab_c from x", "b_c") | expect_equal(expected: false)?

test "case collisions and reserved names are flagged":
	files := ["a/Lib.ms", "a/lib.ms", "b/aux.ms", "c/ok.ms"]
	path_names(files).length() | expect_equal(expected: 2)?

test "a compiler crate may not reach the runtime":
	layering_violation("ms-lower", "ms-rt").is_some() | expect_equal(expected: true)?
	(
		layering_violation("ms-lower", "ms-rt-abi").is_some()
		| expect_equal(expected: false)?
	)

test "a runtime crate may not reach the compiler":
	(
		layering_violation("ms-std-fs", "ms-check").is_some()
		| expect_equal(expected: true)?
	)
	(
		layering_violation("ms-std-fs", "ms-std-path").is_some() | expect_equal(
			expected: false
		)?
	)

test "dev dependencies are ignored":
	manifest := "[dependencies]\nms-check = \{ path = \"../ms-check\" \}\n[dev-dependencies]\nms-rt = \{ path = \"../ms-rt\" \}\n"
	normal_dependencies(manifest) | expect_equal(expected: ["ms-check"])?

test "only the api, editor and tests may name the editor module":
	allowed_to_name_editor("crates/ms-check/src/api.rs") | expect_equal(expected: true)?
	(
		allowed_to_name_editor("crates/ms-check/src/x_tests.rs") | expect_equal(
			expected: true
		)?
	)
	(
		allowed_to_name_editor("crates/ms-check/src/calls.rs") | expect_equal(
			expected: false
		)?
	)
