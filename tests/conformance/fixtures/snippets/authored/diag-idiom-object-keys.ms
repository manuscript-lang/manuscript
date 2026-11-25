// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := Object.keys(1)
}
// expect-error: MS2001 5:10 unknown binding Object; use the prelude List[T] and Map[K, V] types without imports; read a Map with m.keys(), m.values() or m.entries()
