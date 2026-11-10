type Broken[A = Int, B, C = B]:
    first: A
    value: C

fn read(value: Broken[Int, String]) String: value.value

fn call() Int:
    value := Broken[Int, String](1, "kept")
    return read(value).length()
