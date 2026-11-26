// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=agent token study: String.take and String.drop
import stdout from "@std/io/io.ms"

fn main() Void {
	var out = stdout()
	s := "héllo"
	out.write(
		s.view(0, 3) + "|" + s.view(3, s.length()) + "|" + s.view(
			0,
			s.length(),
		) + "|" + s.view(s.length(), s.length()) + "|" + s.view(0, s.length()) + "\n"
	).get()
}
// expect-exit: 0
// expect-stdout: hé|llo|héllo||héllo
