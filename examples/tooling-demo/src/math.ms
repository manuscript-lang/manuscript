import panic from "@std/faults.ms"
import range from "@std/collections.ms"

# Sum three integer values with explicit named arguments.
export fn total(first: Int, second: Int, third: Int) Int:
    return first + second + third

# Work long enough to produce visible CPU samples.
export fn compute(iterations: Int) Int:
    var result = 0
    for index in range(0, iterations):
        result += index % 7
    return result

test "named arguments":
    if total(10, 20, 30) != 60:
        return panic("named argument result differs")
