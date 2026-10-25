type Shape:
    case Circle(radius: Float)
    case Label(text: String)
    case Names(items: List[String])

impl Shape:
    def text() -> ref Optional[String]:
        match ref self:
            case Label(text): return some(text)
            case _: return none

    def names() -> ref Optional[List[String]]:
        match ref self:
            case Names(items): return some(items)
            case _: return none

    def first() -> ref Optional[String]:
        match ref self:
            case Names(items): return some(items.get(0))
            case _: return none

def label_length(shape: Shape) -> Int:
    if let text = shape.text():
        return text.length()

    return 0
