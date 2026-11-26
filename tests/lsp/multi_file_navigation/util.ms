export type Point {
	x, y Int
}

fn Point.norm() Int {
	return self.x * self.x + self.y * self.y
}

export fn scale(p Point, k Int) Point {
	return Point(x: p.x * k, y: p.y * k)
}

export enum Shade {
	Dark
	Light
}
