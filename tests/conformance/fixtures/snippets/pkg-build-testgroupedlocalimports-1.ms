# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:562 TestGroupedLocalImports
export type Value:
    value: Int

export def read(value: Value) -> Int:
    return value.value

def hidden() -> Int:
    return 1
