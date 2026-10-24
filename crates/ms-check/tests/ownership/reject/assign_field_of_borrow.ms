type Cell:
    items: List[Int]

def f(var cells: List[Cell]) -> Unit:
    let first = cells[0]
    first.items = []  # error: only borrows
