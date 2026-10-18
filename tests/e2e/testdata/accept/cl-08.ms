import panic from "@std/faults.ms"

fn selected_sum(values: List[Int]) Int:
    var total = 0

    for value in values:
        if value == 0:
            continue
        if value < 0:
            break

        total += value

    return total

test "iteration control":
    if not (selected_sum([2, 0, 3, -1, 9]) == 5):
        return panic("check failed")
    if not (selected_sum([]) == 0):
        return panic("check failed")
