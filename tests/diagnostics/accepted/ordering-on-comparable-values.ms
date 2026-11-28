// conform: tags=diagnostics,types,generics,tier-core
// conform: phase=check,parse
type Version {
	major Int
}

fn Version.compare(other Version) Int {
	return self.major - other.major
}

fn less[T Comparable](left, right T) Bool {
	return left < right
}

fn main() Void {
	print(Version(1) < Version(2))
	print(less(Version(3), Version(2)))
	print(less("a", "b"))
	print(1.5 >= 2.5)
}
// expect-exit: 0
