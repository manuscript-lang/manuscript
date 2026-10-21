# conform: tags=faults,modules,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=tests/e2e/project_check_test.go:21 TestCLIProjectCheck
import panic from "@std/core.ms"

export fn main() Int:
    return panic("check must not execute main")
