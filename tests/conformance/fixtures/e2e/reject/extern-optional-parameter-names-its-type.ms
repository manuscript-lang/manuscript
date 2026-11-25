// conform: tags=types,diagnostics,tier-core
// conform: phase=check
// An Optional parameter has an implicit default, but what an extern rejects is its type: the message names that
// rather than a default the author never wrote.
extern fn maybe(value Int?) Int

export fn main() Int {
	return 0
}
// expect-error: MS3000 5:17 extern parameter value has type Optional, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them
