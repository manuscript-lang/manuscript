type Shape:
    case Label(text: String)

impl Shape:
    fn text() ref String?:  # error: returns `ref`, but no `return` gives back part of a parameter
        let owned = "x"
        return owned
