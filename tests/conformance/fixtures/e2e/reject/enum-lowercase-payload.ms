// conform: tags=testing,tier-core
// conform: phase=check
enum Keyword {
	case(value Int)
}

fn read(value Keyword) Int {
	match value {
		case => return 0
	}
}
// expect-error: MS3000 9:9 case payload arity mismatch; case has 1 payload fields, found 0 bindings (use _ to ignore one)
