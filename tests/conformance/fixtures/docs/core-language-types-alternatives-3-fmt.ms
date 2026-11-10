// conform: tags=alternatives,formatter,parser,records,tier-core,scope-cleanup
// conform: phase=parse
// conform: origin=documentation/core-language/types/alternatives.md:38
enum LeftState:
    Ready

enum RightState:
    Ready

left: LeftState = LeftState.Ready
// Rejected: two visible Ready cases, even with an annotation.
annotated: LeftState = Ready
// Rejected: two visible Ready cases.
ambiguous := Ready
// Rejected: a different nominal alternative.
wrong: LeftState = RightState.Ready
