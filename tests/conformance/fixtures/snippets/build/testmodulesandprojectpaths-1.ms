# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:238 TestModulesAndProjectPaths
export type Identity:
    value: Int

export fn read(value: Identity) Int:
    return value.value
