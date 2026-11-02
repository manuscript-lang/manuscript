# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:562 TestGroupedLocalImports
export type Value:
    value: Int

export fn read(value: Value) Int:
    return value.value

fn hidden() Int:
    return 1
