import Point, Shade, scale from "./util.ms"

fn main() Void {
	p := Point(x: 1, y: 2)
	q := scale(p, 3)
	print(q.norm())

	s := Shade.Dark

	match s {
		Dark => print("d")
		Light => print("l")
	}
}
