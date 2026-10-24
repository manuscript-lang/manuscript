type Shape:
    case Circle(r: Int)
    case Name(s: String)

def total(xs: List[Int]) -> Int:
    var n = 0
    for x in xs:
        n += x
    return n

def area(shape: Shape) -> Int:
    match shape:
        case Circle(r): return r * r
        case Name(text): return text.length()

def copy_all(xs: List[String]) -> List[String]:
    var out: List[String] = []
    for x in xs: out.append(x.clone())
    return out

def name_of(shape: Shape) -> String:
    match shape:
        case Name(text): return text
        case _: return ""

export def main() -> Int:
    let numbers = [1, 2, 3]
    let words = ["a", "b"]
    let shape = Name("abc")
    # Reading a parameter in a loop or a match borrows it, so the arguments stay usable.
    let sum = total(numbers) + total(numbers)
    let size = area(shape) + area(shape)
    let copy = copy_all(words)
    # Moving a part out makes the function take the parameter at its last use.
    let name = name_of(shape)
    if sum + size + copy.length() + name.length() == 12 + 6 + 2 + 3:
        return 0
    return 1
