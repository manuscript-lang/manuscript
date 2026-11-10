// Handle to a value an Arena[T] owns: a slot index with a generation in the upper bits. It is a scalar, so it copies freely, and a stale handle (its value was removed) reads as none.
export enum Id[T]:
	// Raw handle: `generation * 2^32 + slot`.
	At(raw: Int)

/*
Owns many values of one type in a single flat list and hands out `Id[T]` handles instead of references.
Use it for graphs, trees and cross-linked records: the arena is the one owner, links are plain Ints, and dropping the arena drops every value at once.
Removing a value bumps its slot's generation, so an old handle is rejected instead of reading a reused slot.
*/
export type Arena[T]:
	// Values by slot; `none` marks a free slot. Internal state: use the operations, not this field.
	slots: List[T?] = []
	// Generation of each slot, advanced on removal. Internal state.
	gens: List[Int] = []
	// Free slot indexes, reused last-in first-out. Internal state.
	free: List[Int] = []

impl Arena[T]:
	// Moves a value into the arena and returns its handle.
	var fn add(value: T) Id[T]:
		if self.free.length() > 0:
			slot := self.free.pop().get(0)
			self.slots.set(slot, value)
			return At(self.gens.get(slot) * 4294967296 + slot)

		slot := self.slots.length()
		self.slots.append(value)
		self.gens.append(0)
		return At(slot)

	// Returns the slot a live handle names, or none for a stale or foreign handle.
	fn slot_of(id: Id[T]) Int?:
		match id:
			At(raw):
				slot := raw % 4294967296
				if slot >= self.slots.length(): return none
				if self.gens.get(slot) != raw / 4294967296: return none
				if self.slots.get(slot).is_none(): return none

				return slot

	// Borrows the value `id` names, or none when it was removed. `if var v = arena.get(id)` changes it in place.
	fn get(id: Id[T]) T?:
		slot := self.slot_of(id).get(-1)
		if slot < 0: return none

		return self.slots.get(slot)

	// Reports whether `id` names a live value.
	fn contains(id: Id[T]) Bool:
		return self.slot_of(id).is_some()

	// Removes and returns the value `id` names, or none when it is already gone. The slot is reused with a new generation.
	var fn remove(id: Id[T]) T?:
		slot := self.slot_of(id).get(-1)
		if slot < 0: return none

		self.gens.set(slot, self.gens.get(slot) + 1)
		self.free.append(slot)
		return self.slots.replace(slot, none)

	// Number of live values.
	fn length() Int:
		return self.slots.length() - self.free.length()

	// Calls `change` on the value `id` names, in place, and returns whether it was live.
	var fn update(id: Id[T], change: fn(var T) Unit) Bool:
		slot := self.slot_of(id).get(-1)
		if slot < 0: return false

		// Take the value out, change it, put it back: a move each way, no copy.
		var value = self.slots.replace(slot, none).get()
		change(var value)
		self.slots.set(slot, value)
		return true
