// A view borrows its receiver: changing the receiver while the view is still used is rejected.
export fn main() Int:
    var text = "hello world"
    let word = text.view(0, 5)
    text = "other"
    return word.length()
