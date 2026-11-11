// conform: tags=testing,tier-core
// conform: phase=check
enum ReadError:
	Missing

extern fn read_values() Map[String, Int]!ReadError

export fn main() Int:
	return 0
