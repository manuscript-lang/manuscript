// conform: tags=diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/equality-and-hashing.md:15
interface Equal {
	fn equals(other Equal) Bool
}

interface Hashable {
	fn hash() Int
}
// expect-error: MS2001 4:1 declaration Equal reuses a prelude name; rename it, because Equal always refers to the standard declaration
// expect-error: MS2001 8:1 declaration Hashable reuses a prelude name; rename it, because Hashable always refers to the standard declaration
