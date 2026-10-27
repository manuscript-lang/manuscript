type Cell:
    n: Int
    tag: String

export def main() -> Int:
    var cells = [Cell(n: 1, tag: "a"), Cell(n: 2, tag: "b")]
    let before = cells.clone()
    cells[1].n = 9
    cells[0].tag = "z"
    var grid = [[1], [2]]
    grid[1].append(3)
    if cells[1].n != 9 or cells[0].tag != "z":
        return 1
    if before[1].n != 2 or before[0].tag != "a":
        return 2
    if grid[1].length() != 2:
        return 3
    return 0
