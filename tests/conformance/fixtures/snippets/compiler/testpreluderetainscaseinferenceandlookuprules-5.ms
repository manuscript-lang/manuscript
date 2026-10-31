# conform: tags=alternatives,diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:16 TestPreludeRetainsCaseInferenceAndLookupRules
type Other:
    case Int

fn f() Int?:
    return 1
