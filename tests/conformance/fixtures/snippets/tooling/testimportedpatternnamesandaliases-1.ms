# conform: tags=alternatives,control-flow,diagnostics,interfaces,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:114 TestImportedPatternNamesAndAliases
export type Failure:
    case NotFound
    case Denied(reason: String)

export type Item:
    value: Int

export fn fail() Int!Failure: error(Failure.Denied("denied"))
