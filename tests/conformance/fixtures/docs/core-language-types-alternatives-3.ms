// conform: tags=alternatives,diagnostics,records,tier-core,scope-cleanup
// conform: phase=check
// conform: origin=documentation/core-language/types/alternatives.md:38
enum LeftState {
	Ready
}

enum RightState {
	Ready
}

left LeftState := LeftState.Ready
// Rejected: two visible Ready cases, even with an annotation.
annotated LeftState := Ready
// Rejected: two visible Ready cases.
ambiguous := Ready
// Rejected: a different nominal alternative.
wrong LeftState := RightState.Ready
// expect-error: MS2001 16:14 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
// expect-error: MS2001 14:24 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
// expect-error: MS3001 18:31 expected LeftState, found RightState
