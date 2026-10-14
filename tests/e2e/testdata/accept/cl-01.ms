import panic from "@std/faults.ms"

fn subtract(amount: Int, deduction: Int) -> Int:
    return amount - deduction

test "named multiline call":
    let remaining = subtract(deduction: 2, amount: 9)
    if not (remaining == 7):
        return panic(message: "check failed")
