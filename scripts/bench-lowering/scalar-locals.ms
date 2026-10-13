import List from "@std/collections.ms"

fn integers(limit: Int) -> Int:
    var index = 0
    var total = 0

    while index < limit:
        total = total + index
        index = index + 1

    return total

fn floats(limit: Int) -> Float:
    var index = 0
    var total = 0.5

    while index < limit:
        total = total * 1.0001 + 0.25
        index = index + 1

    return total

fn booleans(limit: Int) -> Bool:
    var index = 0
    var value = false

    while index < limit:
        value = not value
        index = index + 1

    return value

fn floating_values(initial: Float, factor: Float, offset: Float) -> Float:
    var value = initial
    value = value * factor
    value = value + offset
    return value

fn consume_integer(value: Int) -> Unit: return

fn consume_float(value: Float) -> Unit: return

fn forward_integer(input: Int, values: List[Int]) -> Unit:
    let copied = input

    for item in values:
        consume_integer(copied)

fn forward_float(input: Float, values: List[Int]) -> Unit:
    let copied = input

    for item in values:
        consume_float(copied)

fn identity_integer(value: Int) -> Int:
    let copy = value
    return copy

fn identity_float(value: Float) -> Float:
    let copy = value
    return copy
