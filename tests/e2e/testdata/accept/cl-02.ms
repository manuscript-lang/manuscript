import panic from "@std/faults.ms"

fn invalid_division(zero: Int) -> Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    if not (2 + 3 * 4 == 14):
        return panic(message: "check failed")
    if not ((2 + 3) * 4 == 20):
        return panic(message: "check failed")
    if not (10 - 3 - 2 == 5):
        return panic(message: "check failed")
    if not (true or invalid_division(zero: 0)):
        return panic(message: "check failed")
    if not (not (false and invalid_division(zero: 0))):
        return panic(message: "check failed")
