// conform: tags=lists,tier-core
// conform: phase=run
// A constant list of integer literals is read as a view of static data: a copy that is kept or changed is a fresh
// list, and the constant itself never changes.
TABLE := [10, 20, -30, 40]
BYTES List[UInt8] := [1, 2, 255]

fn first_two() Int {
	return TABLE[0] + TABLE[1]
}

fn doubled(values List[Int]) List[Int] {
	return values.map(v => v * 2)
}

fn main() Void {
	var copy = TABLE.clone()
	copy.append(5)
	copy[0] = 99
	moved := TABLE
	print(f"{copy} {moved} {TABLE} {TABLE.length()} {TABLE == [10, 20, -30, 40]}")
	var sum = 0
	for value in TABLE { sum += value }
	print(f"{sum} {first_two()} {doubled(TABLE)} {TABLE.contains(40)} {BYTES}")
	var total = 0
	for round in 0..1000 { total += TABLE[round % 4] }
	print(f"{total} {TABLE.clone()}")
}
// expect-exit: 0
// expect-stdout: [99, 20, -30, 40, 5] [10, 20, -30, 40] [10, 20, -30, 40] 4 true
// expect-stdout: 40 30 [20, 40, -60, 80] true [1, 2, 255]
// expect-stdout: 10000 [10, 20, -30, 40]
