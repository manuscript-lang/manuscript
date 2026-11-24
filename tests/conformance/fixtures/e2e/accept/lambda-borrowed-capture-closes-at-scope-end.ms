// conform: tags=closures,scope-cleanup
// conform: phase=run
type Door:
	name String

fn move Door.close() Void!:
	print("closed " + self.name)

fn size(door Door) Int:
	return door.name.length()

fn main() Void:
	door := Door(name: "front".clone())
	f := fn: size(door)
	print(f())
	print("end")
