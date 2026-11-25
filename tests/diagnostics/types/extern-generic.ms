// conform: tags=testing,tier-core
// conform: phase=check
extern fn identity[T](value T) T

export fn main() Int {
	return 0
}
// expect-error: MS3000 3:1 an extern fn cannot be generic; declare the concrete types the native symbol takes
// expect-error: MS3000 3:23 extern parameter value has type T, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them
// expect-error: MS3000 3:32 extern result has type T, which cannot cross the native boundary; an extern returns sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them, Void, or a Result of one
