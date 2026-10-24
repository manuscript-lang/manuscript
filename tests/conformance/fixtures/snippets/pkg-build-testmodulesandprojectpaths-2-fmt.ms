# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:239 TestModulesAndProjectPaths
from "@value" import Identity
from "@domain/value.ms" import read

export def main() -> Int:
    return read(value: Identity(value: 0))
