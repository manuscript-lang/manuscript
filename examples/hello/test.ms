import panic from "@std/faults.ms"

test "getting started":
    if not (2 + 3 == 5):
        return panic("arithmetic failed")
