type Pair[A, B]:
    value: Int

fn double[T: Clonable](_value: T) Pair[T, T]:
    return Pair[T, T](0)

export fn main() Int:
    v0 := 1
    v1 := double(v0)
    v2 := double(v1)
    v3 := double(v2)
    v4 := double(v3)
    v5 := double(v4)
    v6 := double(v5)
    v7 := double(v6)
    v8 := double(v7)
    v9 := double(v8)
    v10 := double(v9)
    v11 := double(v10)
    v12 := double(v11)
    v13 := double(v12)
    v14 := double(v13)
    v15 := double(v14)
    v16 := double(v15)
    v17 := double(v16)
    v18 := double(v17)
    v19 := double(v18)
    v20 := double(v19)
    v21 := double(v20)
    v22 := double(v21)
    v23 := double(v22)
    v24 := double(v23)
    v25 := double(v24)
    v26 := double(v25)
    v27 := double(v26)
    v28 := double(v27)
    v29 := double(v28)
    v30 := double(v29)
    _chosen := match true:
        true: v30
        false: v30
    return 0
