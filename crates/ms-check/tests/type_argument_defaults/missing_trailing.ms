type Broken[A = Int, B]:
    value: B

fn bare(value: Broken) Void: unit

fn partial(value: Broken[Int]) Void: unit
