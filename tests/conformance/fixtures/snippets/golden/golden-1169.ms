// conform: tags=diagnostics
// conform: phase=check
let (
    LOW = 1
    HIGH: Int = LOW + 9
)

fn total() Int:
    var (
        sum = LOW
        extra = HIGH
    )
    sum += extra
    return sum
