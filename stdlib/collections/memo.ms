# A cache of a function's results by argument, so each distinct argument is computed once (Python `functools.cache`, lodash `memoize`).
# `Memo` has no capacity limit or expiry: it suits pure functions over a bounded set of arguments, such as a recursive Fibonacci.
# `var fib = Memo[Int, Int](compute: slow_fib)` then `fib.get(30)` runs `slow_fib(30)` once, however often it is asked.
export type Memo[K: Hashable & Clonable, V: Clonable]:
    # The function that produces the result for an argument. It should be pure: a result is kept and returned for every later request.
    compute: fn(K) V
    # The results computed so far. Internal state: use `get`, `contains` and `clear`.
    results: Map[K, V] = Map[K, V]()

impl Memo[K, V]:
    # Returns a copy of the result for `key`, calling `compute` only when it has not been computed before.
    var fn get(key: K) V:
        if let known = self.results.get(key):
            return known.clone()

        let value = self.compute(key.clone())
        self.results.add(key, value.clone())
        return value

    # Reports whether a result for `key` is already kept.
    fn contains(key: K) Bool:
        return self.results.contains(key)

    # Returns the number of kept results.
    fn length() Int:
        return self.results.length()

    # Forgets every kept result, so the next request computes again.
    var fn clear() Unit:
        self.results = Map[K, V]()
