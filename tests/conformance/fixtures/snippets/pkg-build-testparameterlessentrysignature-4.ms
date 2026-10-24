# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:208 TestParameterlessEntrySignature
export def main[T]() -> Int:
    return 0
