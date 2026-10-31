# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:239 TestModulesAndProjectPaths
import Identity from "@value"
import read from "@domain/value.ms"

export fn main() Int:
    return read(value: Identity(value: 0))
