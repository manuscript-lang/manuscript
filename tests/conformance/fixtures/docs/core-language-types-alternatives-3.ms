# conform: tags=alternatives,diagnostics,records,tier-core,scope-cleanup
# conform: phase=check
# conform: origin=documentation/core-language/types/alternatives.md:38
type LeftState:
    case Ready

type RightState:
    case Ready

let left: LeftState = LeftState.Ready
# Rejected: two visible Ready cases, even with an annotation.
let annotated: LeftState = Ready
# Rejected: two visible Ready cases.
let ambiguous = Ready
# Rejected: a different nominal alternative.
let wrong: LeftState = RightState.Ready
