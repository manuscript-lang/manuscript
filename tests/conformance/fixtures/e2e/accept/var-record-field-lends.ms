// conform: tags=ownership,var-parameters
// conform: phase=run
type Budget:
	left Int
	notes List[String]

type Scanner:
	pos Int
	budget Budget
	done Bool
	label String

fn spend(var budget Budget, note String) Void:
	budget.left -= 1
	budget.notes.append(note.clone())

fn describe(scanner Scanner) String:
	return f"{scanner.label}@{scanner.pos}/{scanner.budget.left}"

fn step(var scanner Scanner, note String) String:
	scanner.pos += 1
	spend(scanner.budget, note)
	scanner.budget.left -= 1
	scanner.done = scanner.pos >= 3
	return describe(scanner)

fn main() Void:
	var scanner = Scanner(0, Budget(10, []), false, "s")
	print(step(scanner, "a"))
	print(step(scanner, "b"))
	print(step(scanner, "c"))
	print(f"{scanner.done} {scanner.budget.left} {scanner.budget.notes.length()}")
