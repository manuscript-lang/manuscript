# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:64 TestLibraryProjectCommandsAndCache
from "@std/test.ms" import fail

export def other() -> Int: return 4

test "unimported":
    return fail("changed unimported test")
