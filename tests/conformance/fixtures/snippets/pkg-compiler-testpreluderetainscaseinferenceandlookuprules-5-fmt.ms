# conform: tags=alternatives,formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:16 TestPreludeRetainsCaseInferenceAndLookupRules
type Other:
    case some(value: Int)
fn f() Optional[Int]:
    return some(value: 1)
