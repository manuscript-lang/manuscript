// conform: tags=diagnostics
// conform: phase=check
type Layer%d[T] {
    left: Layer%d[T]
    right: Layer%d[T]
}
// expect-error: MS1000 3:11-3:12 expected '{', found '%'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
