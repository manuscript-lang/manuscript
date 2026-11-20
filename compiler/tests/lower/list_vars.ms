fn build(n: Int) Int:
	var xs = [0]
	for i in 0..n:
		xs.append(i)
	return xs.length() + xs[0]

fn swap_list() Int:
	var xs = [1]
	xs = [2, 3]
	return xs[1]

fn early(n: Int) Int:
	var xs = [0]

	for i in 0..n:
		xs.append(i)
		if i == 3: return xs.length()

	return xs[0]

fn flags() Int:
	var seen = [true]
	seen.append(false)
	seen.append(true)
	return seen.length()

fn main() Int:
	return build(3) + swap_list() + early(5) + flags()
