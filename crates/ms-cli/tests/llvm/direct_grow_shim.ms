interface Deep:
	fn down(n: Int) Int

type Node:
	k: Int

fn Node.down(n: Int) Int:
	if n == 0: return self.k
	return self.down(n - 1) + 1

fn run(d: Deep, n: Int) Int:
	return d.down(n)

export fn main() Int:
	node := Node(7)
	got := run(node, 3000000)
	print("{got}")
	return 0
