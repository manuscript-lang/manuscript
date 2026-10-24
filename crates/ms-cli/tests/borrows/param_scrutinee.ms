type Shape:
    case Circle(r: Int)
    case Name(s: String)

fn total(xs: List[Int]) Int:
    var n = 0
    for x in xs:
        n += x
    return n

fn area(shape: Shape) Int:
    match shape:
        Circle(r): return r * r
        Name(text): return text.length()

fn copy_all(xs: List[String]) List[String]:
    var out: List[String] = []
    for x in xs: out.append(x.clone())
    return out

fn name_of(shape: Shape) String:
    match shape:
        Name(text): return text
        _: return ""

export fn main() Int:
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
