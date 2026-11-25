// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/library_project_test.go:81 TestLibraryProjectCommandsAndCache
import value from "@lib/value.ms"

export fn main() Int => return value() - 3
// expect-error: MS2002 4:1 unknown import alias @lib; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
