// Field reads of a record parameter the C body checker claims.
type Point:
	x: Int
	y: Int

type Style:
	scale: Float
	shown: Bool

fn sum(p: Point) Int:
	return p.x + p.y

fn far(p: Point) Bool:
	return p.x * p.x + p.y * p.y > 100

fn scaled(s: Style) Float:
	if s.shown: return s.scale * 2.0
	return s.scale
