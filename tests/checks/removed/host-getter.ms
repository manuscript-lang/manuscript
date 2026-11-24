// removed: filesystem()
// use: import the operation itself
// fix: none: the replacement import depends on what the program does with the handle
fn main() Int:
	host := filesystem()
	return host.read_file("a.txt").length()
