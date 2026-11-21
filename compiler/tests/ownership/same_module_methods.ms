type Gate:
	name: String

fn Gate.label() String:
	return self.name

fn Gate.shout() String:
	return self.label()

fn move Gate.close() Void!:
	return ok()

fn use_gate(name: String) Void!:
	gate := Gate(name)
	print(gate.shout())
	gate.close()?

fn close_twice(name: String) Void!:
	gate := Gate(name)
	gate.close()?
	gate.close()?

fn close_parameter(gate: Gate) Void!:
	gate.close()?
