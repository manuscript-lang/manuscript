# conform: tags=alternatives,control-flow,formatter,interfaces,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:114 TestImportedPatternNamesAndAliases
export type Failure:
    case NotFound
    case Denied(reason: String)

export type Item:
    value: Int

export fn fail() Int!Failure: error(Failure.Denied("denied"))
