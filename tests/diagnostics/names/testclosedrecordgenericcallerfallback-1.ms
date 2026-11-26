// conform: tags=control-flow,diagnostics,formatter,generics,mutation,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/record_bounds_test.go:102 TestClosedRecordGenericCallerFallback
fn count[T](value T) Int {
	cell := Cell(0)
	var i = 0

	while i < 1000 {
		cell.bump(1)
		i += 1
	}

	return cell.total
}

fn probe() Int => return count[String]("unused")
// expect-error: MS2001 5:13 unknown binding Cell; declare it with 'Cell := ...' before use, define 'fn Cell(...) T { ... }', or import it from a module
