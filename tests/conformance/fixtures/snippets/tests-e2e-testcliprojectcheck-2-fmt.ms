# conform: tags=faults,formatter,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/project_check_test.go:32 TestCLIProjectCheck
from "@std/core.ms" import panic

test "check must not execute tests":
    return panic("check must not execute tests")
