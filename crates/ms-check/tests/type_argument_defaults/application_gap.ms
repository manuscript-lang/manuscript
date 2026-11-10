type Broken[A = Int, B]:
    value: B

fn generic[A = Int, B]() Int: 1

fn exercise() Int:
    value := Broken[Int](1)
    return generic[Int]() + value.value
