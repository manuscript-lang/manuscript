// conform: tags=testing,tier-core
// conform: phase=check
enum Keyword:
	case(value: Int)

fn read(value: Keyword) Int:
	match value:
		case: return 0
