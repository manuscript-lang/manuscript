type Cell:
    items: List[Int]

fn f(var cells: List[Cell]) Void:
    first := cells[0]
    first.items = []  // error: only borrows
