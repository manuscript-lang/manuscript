// conform: tags=diagnostics
// conform: phase=check
fn work() Bool {
	return (
		Error(
			value: CommandError.Failed(message: "command diagnostic")
		).message() != "command diagnostic"
	)
}
// expect-error: MS3004 6:13 unknown argument value; parameters of Error: details, kind, message
// expect-error: MS2001 6:20 unknown binding CommandError; declare it with 'CommandError := ...' before use, define 'fn CommandError(...) T { ... }', or import it from a module
// expect-error: MS3003 5:9 missing argument message: String in call to Error; add 'message: <String>'
// expect-error: MS3000 7:11 message is not a function (it has type String); only functions and methods can be called, so remove the (...) or call a function instead
