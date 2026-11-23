// conform: tags=stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
import (
	environment, load_environment, set_environment from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "load_environment keeps existing values and takes the last duplicate":
	dir := temporary("ms-env-")?
	path := join([dir.path(), "a.env"])
	write_file(path, "MS_LOAD_A=1\nMS_LOAD_B='two'\nMS_LOAD_D=1\nMS_LOAD_D='2'\n").wait()?
	set_environment("MS_LOAD_A", "kept")?
	set_environment("MS_LOAD_B", null)?
	set_environment("MS_LOAD_D", null)?
	load_environment(path)?

	env := environment()?
	expect_equal(env.get_or("MS_LOAD_A", ""), "kept")?
	expect_equal(env.get_or("MS_LOAD_B", ""), "two")?
	expect_equal(env.get_or("MS_LOAD_D", ""), "2")?

test "load_environment errors change nothing":
	dir := temporary("ms-env-")?
	path := join([dir.path(), "b.env"])
	write_file(path, "MS_LOAD_C=1\nexport  =bad\n").wait()?
	set_environment("MS_LOAD_C", null)?
	expect_equal(load_environment(path).err().kind.clone().get_or(""), "EBADMSG")?
	expect_false((environment()?).contains("MS_LOAD_C"))?
	expect_equal(load_environment(path, 3).err().kind.clone().get_or(""), "EOVERFLOW")?
	expect_equal(load_environment(dir.path()).err().kind.clone().get_or(""), "EINVAL")?
