# conform: tags=faults,formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/project_check_test.go:21 TestCLIProjectCheck
import panic from "@std/faults.ms"

export fn main() Int:
    return panic("check must not execute main")
