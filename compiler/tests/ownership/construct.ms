type Pair:
	left: Int
	right: Int

type Named:
	name: String
	count: Int

fn make(a: Int, b: Int) Pair:
	return Pair(a, b)

fn label(n: String) Named:
	return Named(n, 1)

fn twice(n: String) Int:
	first := Named(n, 1)
	second := Named(n, 2)
	return first.count + second.count

fn copied() Int:
	p := Pair(1, 2)
	q := Pair(p.left, p.right)
	return q.left
