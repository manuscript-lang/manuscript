// conform: tags=testing,tier-io
// conform: phase=test
import (
	Signal, kill, spawn from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "Subprocess.kill ends the child with Kill by default" {
	child := spawn("cat", [])?
	child.kill()?
	expect_equal((child.wait()?), -1)?
}

test "Subprocess.kill with Terminate ends the child" {
	child := spawn("cat", [])?
	child.kill(Signal.Terminate)?
	expect_equal((child.wait()?), -1)?
}

test "kill ends any process by pid and a gone process is ENOENT" {
	child := spawn("cat", [])?
	expect_true(child.pid() > 0)?
	kill(child.pid())?
	expect_equal((child.wait()?), -1)?
	expect_equal(kill(child.pid(), Signal.Terminate).err().kind, "ENOENT")?
}

test "kill with Interrupt ends a child that does not handle it" {
	child := spawn("cat", [])?
	kill(child.pid(), Signal.Interrupt)?
	expect_equal((child.wait()?), -1)?
}

test "Stop suspends a child and Continue resumes it" {
	child := spawn("cat", [])?
	child.kill(Signal.Stop)?
	child.kill(Signal.Continue)?
	child.kill()?
	expect_equal((child.wait()?), -1)?
}
