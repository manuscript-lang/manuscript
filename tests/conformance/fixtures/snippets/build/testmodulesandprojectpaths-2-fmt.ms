// conform: tags=formatter,modules,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:239 TestModulesAndProjectPaths
import (
	read from "@domain/value.ms",
	Identity from "@value",
)

export fn main() Int {
	return read(value: Identity(value: 0))
}
