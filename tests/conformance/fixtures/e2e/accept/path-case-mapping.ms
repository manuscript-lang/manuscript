// conform: tags=testing,tier-io
// conform: phase=test
import (
	posix, win32 from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",
)

test "Windows relative paths retain scalar lowercase comparisons":
	paths := win32()
	expect_equal(paths.relative("C:/ΟΣ", "C:/οσ")?, "")?
	expect_equal(paths.relative("C:/ΟΣ/a", "C:/οσ/b")?, "..\\b")?
	expect_equal(paths.relative("C:/AΣ.TXT/a", "C:/aσ.txt/b")?, "..\\b")?
	expect_equal(paths.relative("C:/AΣ́/a", "C:/aσ́/b")?, "..\\b")?
	expect_equal(paths.relative("C:/ΟΣ/a", "C:/ος/b")?, "..\\..\\ος\\b")?
	expect_equal(paths.relative("C:/İ/a", "C:/i̇/b")?, "..\\b")?
	expect_equal(paths.relative("C:/Alpha/a", "c:/alpha/b")?, "..\\b")?

test "Windows UNC roots retain scalar lowercase comparisons":
	paths := win32()
	expect_equal(paths.relative("//ΟΣ/share/a", "//οσ/share/b")?, "..\\b")?
	expect_equal(paths.relative("//host/ΟΣ/a", "//host/οσ/b")?, "..\\b")?
	expect_equal(
		paths.resolve("//ΟΣ/share/base", ["//οσ/share/child"])?,
		"\\\\οσ\\share\\child",
	)?

test "POSIX path comparison remains case sensitive":
	expect_equal(posix().relative("/ΟΣ", "/οσ")?, "../οσ")?
	expect_equal(posix().relative("/ΟΣ", "/ος")?, "../ος")?
