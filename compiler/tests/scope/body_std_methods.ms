// Methods of standard types, found through the impls of the imported module: a call of
// an imported function gives the receiver, whose type argument fixes the method's
// parameter.
import stdout from "@std/io/io.ms"

fn say(text: String) Void:
	written := stdout().write(text)
	return

fn wrong() Void:
	written := stdout().write(3)
	return

fn discarded(text: String) Void:
	stdout().write(text)
