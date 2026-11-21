fn inside() Int:
	return [1, 2, 3][1] + [4, 5][-1]

fn past_end() Int:
	return [1, 2][2]

fn before_start() Int:
	return [1, 2][-3]

fn main() Int:
	return inside()
