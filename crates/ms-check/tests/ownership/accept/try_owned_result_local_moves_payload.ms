type Big:
    items: List[Int]

fn make() Big?!:
    return ok(Big(items: [1]))

fn collect(var out: List[Big]) Unit!:
    r := make()
    if found := try r: out.append(found)
    return ok(unit)

fn forward(var out: List[Big]) Unit:
    r := make()
    if found := r.get(): out.append(found)
