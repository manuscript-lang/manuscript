type Door:
	open: Bool

fn move Door.close() Void!:
	return ok()

type Room:
	door: Door
	size: Int

fn size_of(room: Room) Int:
	return room.size

fn pass(move door: Door) Void:
	_held := door
	return

fn forward(door: Door) Void:
	pass(door)
