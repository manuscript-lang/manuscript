import {filled} from "@std/collections.ms"
import panic from "@std/faults.ms"

fn make_cells() -> List[Int]:
    if let values = filled(value: 0, count: 16384): return values

    return panic("fill failure")

export fn main() -> Int:
    var cells = make_cells()
    var next = make_cells()
    var i = 0

    while i < 16384:
        var value = 0
        if (i * 17 + i / 128 * 13) % 7 < 3: value = 1
        cells.set(index: i, value: value)
        i = i + 1

    var generation = 0

    while generation < 50:
        var y = 0

        while y < 128:
            var x = 0

            while x < 128:
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
                x = x + 1

            y = y + 1

        let old = cells
        cells = next
        next = old
        generation = generation + 1

    var sum = 0
    i = 0

    while i < 16384:
        sum = sum + cells.at(i).unwrap()
        i = i + 1

    if sum != 3914: return panic("life checksum")

    return 0
