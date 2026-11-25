// conform: tags=faults,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=run,parse
// conform: origin=tests/e2e/project_check_test.go:21 TestCLIProjectCheck
import panic from "@std/core.ms"

export fn main() Int {
	return panic("check must not execute main")
}
// expect-exit: 134
// expect-stderr: check must not execute main
// expect-stderr:   at testcliprojectcheck-1.ms:7 in main
