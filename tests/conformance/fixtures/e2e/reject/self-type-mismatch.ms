// conform: tags=testing,tier-core
// conform: phase=check
type Key {
	id Int
}

type Other {
	id Int
}

fn Key.equals(other Key) Bool {
	return self.id == other.id
}

fn same[T Equal](left T, right T) Bool {
	return left.equals(right)
}

export fn main() Int {
	key := Key(1)
	other := Other(1)
	if key.equals(other) { return 1 }

	return 0
}
// expect-error: MS3001 22:19 expected Key, found Other (in argument 'other' of key.equals)
