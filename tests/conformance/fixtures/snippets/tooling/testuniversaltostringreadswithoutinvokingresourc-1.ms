# conform: tags=diagnostics,generics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/effects_test.go:100 TestUniversalToStringReadsWithoutInvokingResources
fn text[T](value: T) String:
    return value.to_string()
