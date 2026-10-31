fn fill(var xs: List[Int]) Unit:
    xs.append(1)

fn f() Unit:
    fill(var [1])  # error: must be a variable
