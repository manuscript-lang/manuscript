# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:238 TestModulesAndProjectPaths
export type Identity:
    value: Int

export def read(value: Identity) -> Int:
    return value.value
