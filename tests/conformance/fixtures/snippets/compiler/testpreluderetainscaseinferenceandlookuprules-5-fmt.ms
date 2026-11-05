// conform: tags=alternatives,formatter,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/prelude_test.go:16 TestPreludeRetainsCaseInferenceAndLookupRules
enum Other:
    case Int

fn f() Int?:
    return 1
