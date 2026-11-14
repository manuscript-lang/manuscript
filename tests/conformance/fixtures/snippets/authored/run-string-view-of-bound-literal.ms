// conform: tags=strings,tier-core
// conform: phase=run
export fn main() Int:
    text := "hello"
    middle := text.view(1, 3)
    print(middle)
    nested := "world".view(1, 4).view(1, 2)
    print(nested)
    return 0
