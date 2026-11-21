fn pick(a: Int?, b: Int?) Int:
	match a:
		x:
			match b:
				y:
					return x + y
				none:
					return x
		none:
			return 0

fn main() Void:
	print(f"{pick(1, 2)}")
