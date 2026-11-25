// conform: tags=testing,tier-core
// conform: phase=check
enum ReadError {
	Missing
}

extern fn read_values() Map[String, Int]!ReadError

export fn main() Int {
	return 0
}
// expect-error: MS3000 7:25 extern Result value has type Map, which cannot cross the native boundary; an extern Result holds sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them, or Void
