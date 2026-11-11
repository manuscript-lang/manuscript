import panic from "@std/core.ms"

fn optional(value: Int) Int?: return value

fn result(value: Int) Int!: return ok(value)

fn then_branch() Int:
	while true:
		if panic("stop"): break

fn else_branch() Int:
	while true:
		if panic("stop"):
			continue
		else:
			break

fn optional_then_branch() Int:
	while true:
		if _value := optional(panic("stop")): break

fn optional_else_branch() Int:
	while true:
		if _value := optional(panic("stop")):
			continue
		else:
			break

fn nested_loop() Int:
	while true:
		while true:
			break
		if panic("stop"): break

fn callback() Int:
	f: fn() Int := fn() Int:
		while true:
			if panic("stop"): break
	return f()

fn result_branch() Int:
	while true:
		if _value := result(panic("stop")): break
