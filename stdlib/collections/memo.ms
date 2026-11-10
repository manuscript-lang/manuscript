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

// The key `Memo2` files results under: both arguments together. Internal: use `Memo2.get`.
export type Memo2Key[A: Hashable & Clonable, B: Hashable & Clonable]:
	// The first argument of the memoized call, kept as part of the lookup key.
	a: A
	// The second argument of the memoized call, kept as part of the lookup key.
	b: B

/*
A `Memo` for a function of two arguments: `get(a, b)` computes once per distinct pair.
`var grid = Memo2[Int, Int, Int](compute: fn r, c: r * c)` then `grid.get(3, 4)` returns `12`.
*/
export type Memo2[A: Hashable & Clonable, B: Hashable & Clonable, V: Clonable]:
	// The function that produces the result for an argument pair. It should be pure.
	compute: fn(A, B) V
	// The results computed so far. Internal state: use `get`, `contains` and `clear`.
	results: Map[Memo2Key[A, B], V] = Map[Memo2Key[A, B], V]()

impl Memo2[A, B, V]:
	// Returns a copy of the result for `(a, b)`, calling `compute` only when the pair has not been computed before.
	var fn get(a: A, b: B) V:
		key := Memo2Key[A, B](a: a.clone(), b: b.clone())
		if known := self.results.get(key): return known.clone()

		value := self.compute(a, b)
		self.results.add(key, value.clone())
		return value

	// Reports whether a result for `(a, b)` is already kept.
	fn contains(a: A, b: B) Bool:
		return self.results.contains(Memo2Key[A, B](a: a.clone(), b: b.clone()))

	// Returns the number of kept results.
	fn length() Int:
		return self.results.length()

	// Forgets every kept result, so the next request computes again.
	var fn clear() Unit:
		self.results = Map[Memo2Key[A, B], V]()

// The key `Memo3` files results under: all three arguments together. Internal: use `Memo3.get`.
export type Memo3Key[
	A: Hashable & Clonable, B: Hashable & Clonable, C: Hashable & Clonable
]:
	// The first argument of the memoized call, kept as part of the lookup key.
	a: A
	// The second argument of the memoized call, kept as part of the lookup key.
	b: B
	// The third argument of the memoized call, kept as part of the lookup key.
	c: C

/*
A `Memo` for a function of three arguments: `get(a, b, c)` computes once per distinct triple.
For more arguments, group them in a `type` and use `Memo`.
*/
export type Memo3[
	A: Hashable & Clonable, B: Hashable & Clonable, C: Hashable & Clonable, V: Clonable
]:
	// The function that produces the result for an argument triple. It should be pure.
	compute: fn(A, B, C) V
	// The results computed so far. Internal state: use `get`, `contains` and `clear`.
	results: Map[Memo3Key[A, B, C], V] = Map[Memo3Key[A, B, C], V]()

impl Memo3[A, B, C, V]:
	// Returns a copy of the result for `(a, b, c)`, calling `compute` only when the triple has not been computed before.
	var fn get(a: A, b: B, c: C) V:
		key := Memo3Key[A, B, C](a: a.clone(), b: b.clone(), c: c.clone())
		if known := self.results.get(key): return known.clone()

		value := self.compute(a, b, c)
		self.results.add(key, value.clone())
		return value

	// Reports whether a result for `(a, b, c)` is already kept.
	fn contains(a: A, b: B, c: C) Bool:
		return self.results.contains(
			Memo3Key[A, B, C](a: a.clone(), b: b.clone(), c: c.clone())
		)

	// Returns the number of kept results.
	fn length() Int:
		return self.results.length()

	// Forgets every kept result, so the next request computes again.
	var fn clear() Unit:
		self.results = Map[Memo3Key[A, B, C], V]()
