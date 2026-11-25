// conform: tags=diagnostics,maps,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:69 TestCollectionPreludeAndShadowing
type Map[K, V] {
	value V
}

fn f() Void {
	xs := {1: 2}
}
// expect-error: MS2001 4:1 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
