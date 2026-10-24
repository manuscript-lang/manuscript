# conform: tags=control-flow,modules,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/library_project_test.go:30 TestLibraryProjectCommandsAndCache
from "@std/testing.ms" import fail

export def other() -> Int: return 4

test "unimported":
    if other() != 4: return fail("bad other")
