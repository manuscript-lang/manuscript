# conform: tags=faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=internal/cli/project_check_test.go:53 TestProjectCheckDiscoveryAndReporting
from "@std/core.ms" import panic

test "never execute":
    return panic("check executed code")
