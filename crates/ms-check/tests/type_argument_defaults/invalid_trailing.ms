type Broken[A = Int, B = Missing]:
    value: B

fn bare(value: Broken) Void: void

fn partial(value: Broken[Int]) Void: void
