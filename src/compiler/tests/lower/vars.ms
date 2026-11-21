fn bump(var count: Int, by: Int) Void:
	count += by

fn twice(var count: Int) Void:
	bump(count, 1)
	bump(count, 1)

fn clamp(var value: Int, limit: Int) Void:
	if value > limit: value = limit

fn done(flag: Bool) Void:
	if flag: return
	return

fn main() Int:
	var x = 1
	bump(x, 2)
	twice(x)
	clamp(x, 3)
	done(true)
	return x
