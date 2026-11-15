type Broken[A = Int, B]:
    value: B

fn bare(value: Broken) Void: void

fn partial(value: Broken[Int]) Void: void
