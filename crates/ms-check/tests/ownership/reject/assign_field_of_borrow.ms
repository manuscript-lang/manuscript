type Cell:
    items: List[Int]

fn f(var cells: List[Cell]) Unit:
    first := cells[0]
    first.items = []  // error: only borrows
