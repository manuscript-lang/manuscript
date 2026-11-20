fn first(xs: List[Int]) Int:
	return xs[0]

fn local_list() Int:
	xs := [1, 2, 3]
	return xs[1]

fn bad_entry() List[Int]:
	return [1, 2.5]

fn bad_annotated() Int:
	xs: List[Float] := [1, 2]
	return 1

fn mixed() Int:
	xs := [2.5, 1]
	return 1

fn empty() Int:
	xs: List[Int] := []
	return 1
