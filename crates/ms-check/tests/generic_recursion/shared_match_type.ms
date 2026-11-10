type Pair[A, B]:
    value: Int

fn double[T: Clonable](_value: T) Pair[T, T]:
    return Pair[T, T](0)

fn main() Unit:
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
    let v19 = double(v18)
    let v20 = double(v19)
    let v21 = double(v20)
    let v22 = double(v21)
    let v23 = double(v22)
    let v24 = double(v23)
    let v25 = double(v24)
    let v26 = double(v25)
    let v27 = double(v26)
    let v28 = double(v27)
    let v29 = double(v28)
    let v30 = double(v29)

    let _chosen = match true:
        true: v30
        false: v30
