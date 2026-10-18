import {filled, range} from "@std/collections.ms"
import panic from "@std/faults.ms"

fn make_cells() List[Int]:
    match filled(value: 0, count: 16384):
        ok(values): return values
        error(_): return panic("fill failure")

export fn main() Int:
    var cells = make_cells()
    var next = make_cells()

    for i in range(0, 16384):
        var value = 0
        if (i * 17 + i / 128 * 13) % 7 < 3: value = 1
        cells.set(index: i, value: value)

    for generation in range(0, 50):
        for y in range(0, 128):
            for x in range(0, 128):
                var neighbors = 0
                var dy = -1

                while dy <= 1:
                    var dx = -1

                    while dx <= 1:
                        if dx != 0 or dy != 0:
                            let index = (
                                (
                                    (y + dy + 128)
                                    % 128
                                ) * 128
                                + (x + dx + 128) % 128
                            )
                            neighbors = neighbors + cells.at(index).unwrap()

                        dx = dx + 1

                    dy = dy + 1

                let index = y * 128 + x
                let alive = (
                    neighbors == 3
                    or (
                        neighbors == 2
                        and cells.at(index).unwrap() == 1
                    )
                )
                var value = 0
                if alive: value = 1
                next.set(index: index, value: value)

        let old = cells
        cells = next
        next = old

    var sum = 0
    for i in range(0, 16384):
        sum = sum + cells.at(i).unwrap()
    if sum != 3914: return panic("life checksum")

    return 0
