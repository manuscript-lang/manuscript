// conform: tags=diagnostics
// conform: phase=check
enum Failure {
	NotFound
	Denied
}

enum Envelope {
	Pair(left Failure, right Failure)
}

fn use(value Envelope) Int {
	match value {
		Pair(payload, NotFound) => return 1
	}
}
// expect-error: MS3000 14:14 local binding payload is never read; remove it, use it, or name it with a leading '_' to ignore it
