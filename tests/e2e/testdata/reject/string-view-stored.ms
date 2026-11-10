// A view cannot be stored where an owner is needed: `.clone()` keeps the text.
export fn main() Int:
    text := "hello world"
    var words = List[String]()
    words.append(text.view(0, 5))
    return words.length()
