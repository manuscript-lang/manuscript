// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	for i in 3 {
		return i
	}
	return 0
}
// expect-error: MS3000 4:5 for requires List, Set, Map, a ReadStream, or an Iterator, found Int; iterate a collection, e.g. a list literal [1, 2, 3], or implement ReadStream with 'var fn next() T?!' and 'var fn close() Void!', or Iterator with 'var fn next() T?'
