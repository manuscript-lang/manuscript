// conform: tags=control-flow,diagnostics,formatter,testing,tier-core,try-result
// conform: phase=check,parse
// conform: origin=tests/e2e/test_fixture_test.go:196 TestCLITestFixtureInterruptCleansUp
test "interruptible" {
	println("READY")
	while true {
		expect_equal(1, 1)?
	}
}

test "later" {
	fail("must not run")?
}
// expect-error: MS2001 5:5 unknown binding println; there is no println: use print(value), which writes any value and a newline; for write errors or bytes import stdout from "@std/io/io.ms" and call stdout().write("text\\n")
// expect-error: MS2001 7:9 unknown binding expect_equal; add: import expect_equal from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import expect_equal from \"@std/test/test.ms\"\n"
// expect-error: MS2001 12:5 unknown binding fail; add: import fail from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import fail from \"@std/test/test.ms\"\n"
