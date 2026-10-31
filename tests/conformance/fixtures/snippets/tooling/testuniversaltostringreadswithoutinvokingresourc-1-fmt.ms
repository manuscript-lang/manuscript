# conform: tags=formatter,generics,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/effects_test.go:100 TestUniversalToStringReadsWithoutInvokingResources
fn text[T](value: T) String:
    return value.to_string()
