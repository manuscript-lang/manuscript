// conform: tags=diagnostics
// conform: phase=check
type interface {
    value: Int
}
// expect-error: MS1000 3:6-3:15 expected a name, found 'interface'; 'interface' is a reserved word and cannot be used as a name
