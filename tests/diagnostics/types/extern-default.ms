// conform: tags=testing,tier-core
// conform: phase=check
extern fn labs(value Int = 1) Int

export fn main() Int {
	return labs()
}
// expect-error: MS3000 3:16 extern parameter value cannot have a default; the native symbol takes every argument
