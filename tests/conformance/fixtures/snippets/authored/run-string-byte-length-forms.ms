// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// Byte length and emptiness of inline, heap, built and empty strings agree on every backend.
export fn main() Int:
    a := "héllo"
    b := "plain ascii text that is also longer than fifteen bytes"
    c := a + b
    print(a.byte_length())
    print(b.byte_length())
    print(c.byte_length())
    print("".byte_length())
    print(a.is_empty())
    print("".is_empty())
    print(c.is_empty())
    print(b.take(0).is_empty())
    return 0
