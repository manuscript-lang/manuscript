# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:208 TestParameterlessEntrySignature
export fn main[T]() Int:
    return 0
