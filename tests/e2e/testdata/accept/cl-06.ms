import panic from "@std/faults.ms"

fn positive(value: Int) -> Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) -> Unit:
    assert value > 0

test "return contracts":
    assert positive(value: 3) == 3
    discard(value: 1)
