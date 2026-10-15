package msruntime

// PriorityQueue is a local stable binary heap. Shared access uses Synchronized.
// Comparators must be consistent and must not mutate this queue.
type priorityEntry struct {
	value    Value
	sequence uint64
}
type PriorityQueue struct {
	typ      string
	compare  Value
	capacity int
	next     uint64
	items    []priorityEntry
}

func (q *PriorityQueue) before(ctx *Execution, left, right priorityEntry) bool {
	order := Invoke(ctx, q.compare, []Argument{{"left", left.value}, {"right", right.value}}).(int64)
	return order < 0 || order == 0 && left.sequence < right.sequence
}
func (q *PriorityQueue) Operation(name string) Function {
	if name == "length" || name == "is_empty" || name == "peek" {
		Panic("read-only accessor is not a method")
	}
	element := typeArguments(q.typ)[0]
	labels, result := []string{}, "@std/Optional["+element+"]"
	switch name {
	case "enqueue":
		labels, result = []string{"value"}, "Bool"
	case "dequeue":
	default:
		return NewFunction(nil, "Never", func(_ *Execution, _ []Value) Value { return Panic("unknown PriorityQueue operation") })
	}
	return NewFunction(labels, result, func(ctx *Execution, args []Value) Value {
		switch name {
		case "enqueue":
			if q.capacity > 0 && len(q.items) >= q.capacity {
				return false
			}
			entry := priorityEntry{args[0], q.next}
			at := len(q.items)
			for at > 0 {
				parent := (at - 1) / 2
				if !q.before(ctx, entry, q.items[parent]) {
					break
				}
				at = parent
			}
			// Compare before mutating, so a comparator fault leaves the heap intact.
			q.items = append(q.items, entry)
			for i := len(q.items) - 1; i > at; {
				parent := (i - 1) / 2
				q.items[i] = q.items[parent]
				i = parent
			}
			q.items[at] = entry
			q.next++
			return true
		default:
			if len(q.items) == 0 {
				return optional(element, nil, false)
			}
			value := q.items[0].value
			if name == "dequeue" {
				last := len(q.items) - 1
				entry := q.items[last]
				var path []int
				at := 0
				for {
					child := at*2 + 1
					if child >= last {
						break
					}
					if child+1 < last && q.before(ctx, q.items[child+1], q.items[child]) {
						child++
					}
					if !q.before(ctx, q.items[child], entry) {
						break
					}
					path = append(path, child)
					at = child
				}
				at = 0
				for _, child := range path {
					q.items[at] = q.items[child]
					at = child
				}
				if last > 0 {
					q.items[at] = entry
				}
				q.items[last] = priorityEntry{}
				q.items = q.items[:last]
				if last == 0 {
					q.items = nil
					q.next = 0
				}
			}
			return optional(element, value, true)
		}
	})
}
