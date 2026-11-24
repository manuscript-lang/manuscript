// conform: tags=testing,tier-core
// conform: phase=check
// `or_else` takes its receiver, and a lent slice is not its to give.
export fn main() Void!:
	var xs = [1, 2, 3, 4]
	ys := xs.slice(0, 2).or_else(e => ok([]))
	xs.append(5)
	print(ys)
