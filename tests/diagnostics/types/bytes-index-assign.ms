// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	var data = "abc".to_bytes()
	data[0] = 1
	return 0
}
// expect-error: MS3000 5:5 index assignment requires a List[T] or Map[K, V]; Bytes and String are immutable, build a new value instead
