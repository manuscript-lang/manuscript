type Broken[A = Int, B = Missing]:
    value: B

fn bare(value: Broken) Unit: unit

fn partial(value: Broken[Int]) Unit: unit
