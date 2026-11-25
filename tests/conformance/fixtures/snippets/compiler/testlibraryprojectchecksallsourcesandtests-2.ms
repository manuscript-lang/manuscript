// conform: tags=diagnostics,modules,testing,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/library_project_test.go:31 TestLibraryProjectChecksAllSourcesAndTests
import value from "@lib/value.ms"

test "value" {
	n := value()
}
// expect-error: MS2002 4:1 unknown import alias @lib; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
