// conform: tags=testing,tier-core
// conform: phase=check
enum ReadError {
	Failed(reason String)
}

extern fn read_value() Int!ReadError

export fn main() Int {
	return 0
}
// expect-error: MS3000 7:24 extern error type ReadError must be an alternative whose cases carry nothing, `code Int`, `message String`, or both; the native returns the status 1 + the case index and fills code_out and message_out
