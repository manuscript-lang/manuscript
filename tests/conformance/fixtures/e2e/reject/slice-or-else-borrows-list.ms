// conform: tags=testing,tier-core
// conform: phase=check
// `or_else` on a lent slice returns the slice itself, so the list cannot change while it is held.
export fn main() Void!:
	var xs = [1, 2, 3, 4]
	ys := xs.slice(0, 2).or_else(fn e: ok([]))
	xs.append(5)
	print(ys)
