# conform: tags=control-flow,formatter,modules,parser,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:30 TestLibraryProjectCommandsAndCache
import fail from "@std/testing.ms"
export fn other() Int: return 4
test "unimported":
    if other() != 4: return fail("bad other")
