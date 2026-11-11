// Independent checksum oracle for bench/language/life.ms (not a performance
// comparator).

fn main() Int:
	size := 128
	var cells = List[Int](reserve: size * size)
	for i in 0..size * size:
		cells.append(if (i * 17 + i / size * 13) % 7 < 3: 1 else: 0)

	for _step in 0..50:
		var next = List[Int](reserve: size * size)

		for y in 0..size:
			for x in 0..size:
				var neighbors = 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx != 0 or dy != 0:
							neighbors += cells[
								(
									(y + dy + size)
									% size
								) * size + (x + dx + size) % size
							]

				here := cells[y * size + x]
				next.append(
					if neighbors == 3 or (
						neighbors == 2
						and here == 1
					): 1 else: 0
				)

		cells = next

	alive := cells.fold(0, fn(a: Int, c: Int) Int: a + c)

	if alive != 3914:
		print("unexpected live count {alive}")
		return 1

	print("{alive}")
	return 0
