import floor from "@std/math/math.ms"

fn identity(value: Int) Int:
    result := value
    return result

fn caller() Int:
    return identity(1)

fn rounding() Float:
    return floor(1.25)
