type Big:
	items: List[Int]

fn make() Big?!:
	return ok(Big(items: [1]))

fn collect(var out: List[Big]) Unit!:
	r := make()
	if found := r?: out.append(found)

fn forward(var out: List[Big]) Unit:
	r := make()
	if found := r.get(): out.append(found)
