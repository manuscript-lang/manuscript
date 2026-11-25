// conform: tags=diagnostics
// conform: phase=check
type Grow[T] {
	next Bridge
}

type Bridge {
	next Grow[Int]
}
// expect-error: MS3040 8:5 recursive generic applications must preserve their parameters in Bridge.next; keep the same type arguments in the same positions along a recursive cycle
