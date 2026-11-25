// conform: phase=check
// conform: tags=alternatives,diagnostics,parser,tier-core
export opaque type Legacy {
	case Ready
}
// expect-error: MS2001 4:10 unknown type Ready; declare it with 'type Ready:' / 'enum Ready:' / 'interface Ready:', declare it as a type parameter, or import it
