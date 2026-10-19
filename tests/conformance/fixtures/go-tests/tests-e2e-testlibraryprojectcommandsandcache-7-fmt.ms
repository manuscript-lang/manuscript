# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:81 TestLibraryProjectCommandsAndCache
import value from "@lib/value.ms"
export fn main() Int: return value() - 3
