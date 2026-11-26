// conform: tags=diagnostics
// conform: phase=check
type Phantom[T] {
	value Int
}

type Grow[T] {
	value Phantom[Grow[List[T]]]
}
// expect-error: MS3040 8:5 recursive generic applications must preserve their parameters in Grow.value; keep the same type arguments in the same positions along a recursive cycle
