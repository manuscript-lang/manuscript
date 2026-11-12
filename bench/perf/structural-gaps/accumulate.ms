type Cell:
	hits: Int
	sum: Int

type Grid:
	cells: List[Cell]
	total: Int

fn bump(var g: Grid, n: Int) Unit:
	for r in 0..n:
		for i in 0..g.cells.length():
			g.cells[i].hits += 1
			g.cells[i].sum += i
			g.total += 1

fn main() Unit:
	var g = Grid([], 0)
	for i in 0..1000:
		g.cells.append(Cell(0, 0))
	bump(var g, 400000)
	print("{g.total} {g.cells[7].sum}")
