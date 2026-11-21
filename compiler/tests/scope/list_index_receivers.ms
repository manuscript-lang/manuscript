type Box:
	items: List[Int]

fn mk() List[Int]:
	return [1, 2]

fn a() Int:
	return 1

fn b(i: Int) Int:
	return mk()[i]

fn c(bx: Box, i: Int) Int:
	return bx.items[i]

fn d(xs: List[Int], i: Int) Int:
	return xs[i]

fn e(xs: List[List[Int]], i: Int) Int:
	return xs[i][i]

fn f(xs: List[Int]) Int:
	return xs[xs.length() - 1]

fn main() Int:
	return a() + b(0) + c(Box(items: [4]), 0) + d([5], 0) + e([[6]], 0) + f([7])
