// conform: tags=testing,tier-core
// conform: phase=check
extern type Handle[T]

export fn main() Int {
	return 0
}
// expect-error: MS3000 3:1 extern type Handle cannot be generic; declare one extern type per native handle
