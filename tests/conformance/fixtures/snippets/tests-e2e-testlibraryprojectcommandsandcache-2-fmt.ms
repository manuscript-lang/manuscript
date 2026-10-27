# conform: tags=control-flow,formatter,modules,parser,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:30 TestLibraryProjectCommandsAndCache
from "@std/test.ms" import fail

export def other() -> Int: return 4

test "unimported":
    if other() != 4: return fail("bad other")
