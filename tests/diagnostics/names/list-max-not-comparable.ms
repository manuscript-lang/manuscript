// conform: tags=testing,tier-core
// conform: phase=check
type Plain {
	value Int
}

export fn main() Int {
	return [Plain(2)].max().get().value
}
// expect-error: MS2001 8:23 unknown or ambiguous member max on List[Plain]; max requires Plain to be Comparable; Plain does not satisfy Comparable; give Plain the methods Comparable declares, or use a type that implements it
