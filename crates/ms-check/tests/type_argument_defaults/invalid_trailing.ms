type Broken[A = Int, B = Missing]:
    value: B

fn bare(value: Broken) Void: unit

fn partial(value: Broken[Int]) Void: unit
