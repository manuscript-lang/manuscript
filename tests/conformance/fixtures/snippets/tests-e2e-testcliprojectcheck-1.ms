# conform: tags=faults,modules,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=tests/e2e/project_check_test.go:21 TestCLIProjectCheck
from "@std/core.ms" import panic

export def main() -> Int:
    return panic("check must not execute main")
