# Independent checksum oracle for bench/language/life.ms (not a performance comparator).
import stdout from "@std/io/io.ms"

export fn main() Int:
    let size = 128
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

                let here = cells[y * size + x]
                next.append(
                    if neighbors == 3 or (
                        neighbors == 2
                        and here == 1
                    ): 1 else: 0
                )

        cells = next

    let alive = cells.fold(0, fn(a: Int, c: Int) Int: a + c)

    if alive != 3914:
        stdout().write("unexpected live count {alive}\n").get()
        return 1

    stdout().write("{alive}\n").get()
    return 0
