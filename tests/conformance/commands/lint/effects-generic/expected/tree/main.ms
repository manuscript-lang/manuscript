import append_file from "@std/os/fs.ms"

interface Show {
	fn show() Int
}

type Point {
	x Int
}

fn Point.show() Int {
	void append_file("x.txt", "hi")
	return self.x
}

type Door {
	id Int
}

fn move Door.close() Void {
	void append_file("door.txt", "closed")
}

fn twice[T Show](v T) Int {
	return v.show()
}

fn keep[T](v T) Int {
	return 1
}

fn bound() Int {
	return twice(Point(x: 1))
}

fn closes() Int {
	return keep(Door(id: 1))
}

fn pure() Int {
	return keep(3)
}

fn main() Int {
	return bound() + closes() + pure()
}
