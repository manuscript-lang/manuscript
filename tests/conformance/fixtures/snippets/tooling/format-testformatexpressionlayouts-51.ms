// conform: tags=diagnostics,maps,optional,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:377 TestFormatExpressionLayouts
fn work(first Int, second String) (Map[String, String]?)!ApplicationError {
	return error(cause)
}
// expect-error: MS2001 4:58 unknown type ApplicationError; declare it with 'type ApplicationError:' / 'enum ApplicationError:' / 'interface ApplicationError:', declare it as a type parameter, or import it
// expect-error: MS2001 5:18 unknown binding cause; declare it with 'cause := ...' before use, define 'fn cause(...) T { ... }', or import it from a module
