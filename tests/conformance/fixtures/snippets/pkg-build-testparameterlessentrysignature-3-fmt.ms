# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:207 TestParameterlessEntrySignature
export def main(value: Int = 0) -> Int:
    return value
