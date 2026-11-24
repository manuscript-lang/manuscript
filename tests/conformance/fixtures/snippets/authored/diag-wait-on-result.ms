// conform: tags=diagnostics,tier-core
// conform: phase=check
import open from "@std/os/fs.ms"

export fn main() Int! {
	f := open("a").wait()?
	f.close()?
	return 0
}
