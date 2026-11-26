// conform: tags=formatter,lexer,numbers,tier-core
// conform: phase=run,parse
// conform: origin=hex, binary and separator literals
import stdout from "@std/io/io.ms"

fn main() Void {
	a := 0xFF_FF
	b := 0b1010_0101
	c := 1_000_000
	d := -0x10
	e Int32 := 0x7FFF_FFFF
	m := {0xFF: "x"}
	f := 3.141_592
	void stdout().write(
		f"{a} {b} {c} {d} {e} {f} {0xFF} {m[255]} {-0x8000_0000_0000_0000}\n"
	)
}
// expect-exit: 0
// expect-stdout: 65535 165 1000000 -16 2147483647 3.141592 255 x -9223372036854775808
