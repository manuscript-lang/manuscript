// conform: tags=diagnostics
// conform: phase=check
let (
    LOW = 1
    HIGH: Int = LOW + 9
)

fn total() Int {
    var (
        sum = LOW
        extra = HIGH
    )
    sum += extra
    return sum
}
// expect-error: MS1000 3:1-3:4 'let' is not a Manuscript declaration keyword; write 'NAME := value' (or 'NAME: Type := value') for a module constant
