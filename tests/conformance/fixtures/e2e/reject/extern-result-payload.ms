// conform: tags=testing,tier-core
// conform: phase=check
enum ReadError:
	Failed(reason: String)

extern fn read_value() Int!ReadError

export fn main() Int:
	return 0
