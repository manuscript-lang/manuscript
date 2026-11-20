fn first(items: List[Int]) Int:
	return items[0]

fn make() List[Int]:
	return [1, 2, 3]

fn main() Int:
	xs := make()
	return first(xs)
