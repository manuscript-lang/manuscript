/*
A cache of a function's results by argument, so repeated calls reuse the first result.
Use it for a pure function called repeatedly with the same arguments. Entries stay until `clear()`; there is no capacity limit or expiry.
`var squares = Memo[Int, Int](compute: fn n: n * n)` then `squares.get(4)` returns `16`; asking again reads the cached result.
*/
export type Memo[K: Hashable & Clonable, V: Clonable]:
	// The function that produces the result for an argument. It should be pure: a result is kept and returned for every later request.
	compute: fn(K) V
	// The results computed so far. Internal state: use `get`, `contains` and `clear`.
	results: Map[K, V] = Map[K, V]()

impl Memo[K, V]:
	// Returns a copy of the result for `key`, calling `compute` only when it has not been computed before.
	var fn get(key: K) V:
		if known := self.results.get(key): return known.clone()

		value := self.compute(key.clone())
		self.results.add(key, value.clone())
		return value

	// Reports whether a result for `key` is already kept.
	fn contains(key: K) Bool:
		return self.results.contains(key)

	// Returns the number of kept results.
	fn length() Int:
		return self.results.length()

	// Forgets every kept result, so the next request computes again.
	var fn clear() Unit:
		self.results = Map[K, V]()
