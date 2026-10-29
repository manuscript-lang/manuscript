type Shape:
    case Circle(radius: Float)
    case Label(text: String)
    case Names(items: List[String])

impl Shape:
    fn text() ref Optional[String]:
        match self:
            Label(text): return some(text)
            _: return none

    fn names() ref Optional[List[String]]:
        match self:
            Names(items): return some(items)
            _: return none

    fn first() ref Optional[String]:
        match self:
            Names(items): return some(items.get(0))
            _: return none

fn label_length(shape: Shape) Int:
    if let text = shape.text():
        return text.length()

    return 0
