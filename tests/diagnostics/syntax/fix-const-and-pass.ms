// conform: tags=diagnostics,tier-core
// conform: phase=check
const LIMIT = 3
const NAME: String = "a"

fn run() Int {
	if true {
		pass
	}
	return LIMIT
}
// expect-error: MS1000 3:13-3:14 an immutable binding uses ':=' after its type: write 'x Type := value'; '=' binds only after 'var'
// expect-fix: 3:13-3:14 ":="
// expect-error: MS1000 4:1-4:21 'const' is not a Manuscript declaration keyword; write 'NAME := value' (or 'NAME: Type := value') for a module constant
// expect-fix: 4:1-4:21 "NAME: String :="
// expect-error: MS1000 8:9-8:13 'pass' is not a keyword; write 'void' for an empty block or match arm
// expect-fix: 8:9-8:13 "void"
