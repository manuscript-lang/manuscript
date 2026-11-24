// Runs on the oldest glibc that Linux programs support (2.28). CI builds it on a
// current host and runs it in an AlmaLinux 8 container: threads, the resolver pool,
// file metadata, child processes, entropy and libm all reach glibc through the versions
// the link-time stubs bind.
import (
	promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	exp, hypot, log, pow from "@std/math/math.ms",
	lookup from "@std/net/net.ms",
	environment from "@std/os/env.ms",
	stat from "@std/os/fs.ms",
	run from "@std/os/process.ms",
	secure_int from "@std/random.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn square(n Int) Int:
	return n * n

fn main() Void:
	squared := promise(() => ok(square(12))).wait().get_or(-1)
	file := stat("/etc/hosts", follow_links: true).is_ok()
	child := run("true", []).wait().is_ok()
	entropy := secure_int(0, max_exclusive: 10).is_ok()
	hosts := lookup("localhost").is_ok()

	// `environ`, `_environ` and `__environ` must be one object in the stubs (copy relocation).
	env := environment().get().length() > 0
	void sleep(nanoseconds(1000000)).wait()

	math := pow(2.0, 10.0) + exp(0.0) + log(1.0) + hypot(3.0, 4.0)
	stdout().write(f"{squared} {file} {child} {entropy} {hosts} {env} {math}\n").get()
