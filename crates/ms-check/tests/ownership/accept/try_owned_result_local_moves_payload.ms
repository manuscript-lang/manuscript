type Big:
    items: List[Int]

fn make() Big?!:
    return ok(Big(items: [1]))

fn collect(var out: List[Big]) Unit!:
    let r = make()
    if let found = try r: out.append(found)
    return ok(unit)

fn forward(var out: List[Big]) Unit:
    let r = make()
    if let found = r.get(): out.append(found)
