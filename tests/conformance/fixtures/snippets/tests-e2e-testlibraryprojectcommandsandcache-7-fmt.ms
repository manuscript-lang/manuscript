# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:81 TestLibraryProjectCommandsAndCache
from "@lib/value.ms" import value

export def main() -> Int: return value() - 3
