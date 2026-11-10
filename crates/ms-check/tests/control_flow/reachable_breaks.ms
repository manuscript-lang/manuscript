import panic from "@std/core.ms"

fn boolean_condition(flag: Bool) Int:
	while true:
		if flag: break

fn optional_condition(value: Int?) Int:
	while true:
		if item := value: break

fn skipped_panic(flag: Bool) Int:
	while true:
		if flag and panic("stop"): break

fn condition_break(flag: Bool) Int:
	while true:
		if (
			match flag:
				true:
					break
				false: panic("stop")
		):
			continue

fn unreachable_error() Int:
	while true:
		if panic("stop"):
			missing()
			break

fn optional(value: Int) Int?: return value

fn optional_condition_break(flag: Bool) Int:
	while true:
		if _item := optional(
			match flag:
				true:
					break
				false: panic("stop")
		):
			continue
