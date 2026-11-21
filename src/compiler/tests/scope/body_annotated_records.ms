type Pair:
	left: Int
	right: Int

fn sum() Int:
	p: Pair = Pair(1, 2)
	return p.left + p.right

fn mismatch() Int:
	p: Pair = 3
	return 0
