// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:239 TestModulesAndProjectPaths
import (
	read from "@domain/value.ms",
	Identity from "@value",
)

export fn main() Int {
	return read(value: Identity(value: 0))
}
// expect-error: MS2002 4:1 unknown import alias @domain; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
