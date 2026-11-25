// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/analysis_test.go:167 TestAnalysisProjectScopes
import value from "@lib"

export fn main() Int {
	return value()
}
// expect-error: MS2002 4:1 unknown import alias @lib; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
