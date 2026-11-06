type Pair[A, B]:
    value: Int

fn double[T: Clonable](_value: T) Pair[T, T]:
    return Pair[T, T](0)

export fn main() Int:
    let v0 = 1
    let v1 = double(v0)
    let v2 = double(v1)
    let v3 = double(v2)
    let v4 = double(v3)
    let v5 = double(v4)
    let v6 = double(v5)
    let v7 = double(v6)
    let v8 = double(v7)
    let v9 = double(v8)
    let v10 = double(v9)
    let v11 = double(v10)
    let v12 = double(v11)
    let v13 = double(v12)
    let v14 = double(v13)
    let v15 = double(v14)
    let v16 = double(v15)
    let v17 = double(v16)
    let v18 = double(v17)
    let _bad: Int = v18
    return 0
