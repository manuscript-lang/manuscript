// conform: tags=control-flow,tier-core
// conform: phase=run
// conform: origin=break and continue in if let bodies and else branches with condition temporaries

fn maybe(name: String, present: Bool) List[String]?:
	return if present: [name.clone()] else: null

fn stop_in_body() Void:
	for i in 0..3:
		r := maybe(f"body{i}", true)

		if r != null:
			if i == 1: break

			print(f"{r[0]}")

fn skip_in_body() Void:
	for i in 0..3:
		r := maybe(f"skip{i}", true)

		if r != null:
			if i == 1: continue

			print(f"{r[0]}")

fn stop_in_else() Void:
	for i in 0..3:
		r := maybe(f"else{i}", i == 0)

		if r != null:
			print(f"{r[0]}")
		else:
			break

fn skip_in_else() Void:
	for i in 0..3:
		r := maybe(f"else{i}", i != 1)

		if r != null:
			print(f"{r[0]}")
		else:
			continue

fn main() Void:
	stop_in_body()
	skip_in_body()
	stop_in_else()
	skip_in_else()
