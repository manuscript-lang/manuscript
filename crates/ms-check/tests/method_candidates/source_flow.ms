import panic from "@std/core.ms"

type Counter:
	value: Int

fn Counter.next() Counter: Counter(self.value + 1)

fn stop() Int:
	Counter(panic("stop")).next()

fn exit_loop(input: Int?) Unit:
	while true:
		Counter(
			match input:
				value: value
				none: break
		).next()
