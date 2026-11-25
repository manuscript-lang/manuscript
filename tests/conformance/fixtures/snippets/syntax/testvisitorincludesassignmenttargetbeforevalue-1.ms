// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/syntax/walk_test.go:68 TestVisitorIncludesAssignmentTargetBeforeValue
fn update() Void {
	owner().value = replacement()
}
// expect-error: MS2001 5:5 unknown binding owner; declare it with 'owner := ...' before use, define 'fn owner(...) T { ... }', or import it from a module
// expect-error: MS3000 5:13 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
// expect-error: MS2001 5:21 unknown binding replacement; declare it with 'replacement := ...' before use, define 'fn replacement(...) T { ... }', or import it from a module
