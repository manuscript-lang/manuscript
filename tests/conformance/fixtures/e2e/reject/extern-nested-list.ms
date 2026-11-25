// conform: tags=testing,tier-core
// conform: phase=check
extern fn total(values List[List[Int]]) Int

export fn main() Int {
	return total([[1, 2]])
}
// expect-error: MS3000 3:17 extern parameter values has type List, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them
