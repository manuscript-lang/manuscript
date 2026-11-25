// conform: tags=diagnostics
// conform: phase=check
type Mixed {
	value Int
	case Ready
}
// expect-error: MS2001 5:10 unknown type Ready; declare it with 'type Ready:' / 'enum Ready:' / 'interface Ready:', declare it as a type parameter, or import it
