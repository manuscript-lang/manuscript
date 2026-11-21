fn names() List[String]:
	return ["a", "b"]

fn count(xs: List[String]) Int:
	var n = 0
	for s in xs:
		n += 1
	return n

fn keep(xs: List[String]) List[String]:
	return xs

fn main() Int:
	ys := names()
	b := "z"
	zs := ["x", b]
	if ys.length() > 0: return count(ys) + count(zs) + zs.length()

	return 0
"
 right: "fn names() List[String]:
    return ["a", "b"]

fn count(xs: List[String]) Int:
    var n = 0
    for s in xs:
        n = n + 1
    return n

fn keep(xs: List[String]) List[String]:
    return xs

fn main() Int:
    ys := names()
    b := "z"
    zs := ["x", b]
    if ys.length() > 0:
        return count(ys) + count(zs) + zs.length()
    return 0
