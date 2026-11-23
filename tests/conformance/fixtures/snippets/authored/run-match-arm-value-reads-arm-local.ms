// conform: tags=match,tier-core
// conform: phase=run
// A match that ends an arm reads the locals the arm declared before it.
fn pick(code: Int) String:
    match code:
        1:
            word := "one"
            match word.length():
                3: return word
                _: return "other"
        _: return "none"

export fn main() Int:
    print(pick(1))
    print(pick(2))
    return 0
