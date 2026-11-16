// expect-mir: "list.const.view"
// expect-opt-mir-absent: "call @table"
// Reading a constant list (`table[i]`, `length`, `for`) borrows its static data. Each use used to
// evaluate the initializer afresh: an allocation, a copy and a free per read, which made the JPEG
// transform's inner loop spend its time in the allocator.
table := [3, 1, 4, 1, 5, 9, 2, 6]

fn main() Void:
	var s = 0
	for i in 0..8:
		s += table[i]
	print(f"{s} {table.length()}")
