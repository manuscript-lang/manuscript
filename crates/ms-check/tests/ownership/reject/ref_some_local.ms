type Shape:
    case Label(text: String)

impl Shape:
    def text() -> ref Optional[String]:  # error: returns `ref`, but no `return` gives back part of a parameter
        let owned = "x"
        return some(owned)
