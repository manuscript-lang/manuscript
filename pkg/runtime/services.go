package msruntime

import (
	"sync"
)

func ConstructWithContext(ctx *Execution, typ string, args []Argument) Value {
	name, _ := splitType(typ)
	switch name {
	case "@std/TaskGroup":
		return NewTaskGroup(ctx, args)
	case "@std/Scheduler":
		return NewScheduler(ctx, args)
	case "@std/Queue":
		if len(args) == 0 {
			return &Queue{typ: typ}
		}
		value, valid := nativeOption(args[0].Value, "Int", int64(0))
		if !valid {
			return Panic("Queue capacity must be positive")
		}
		capacity := value.(int64)
		if option, ok := args[0].Value.(Alternative); ok && option.Tag == "none" {
			return &Queue{typ: typ}
		}
		if capacity <= 0 || capacity > int64(^uint(0)>>1) {
			return Panic("Queue capacity must be positive")
		}
		return &Queue{typ: typ, capacity: int(capacity)}
	case "@std/PriorityQueue":
		q := &PriorityQueue{typ: typ}
		for _, arg := range args {
			if arg.Name == "compare" {
				q.compare = arg.Value
			}
			if arg.Name == "capacity" {
				value, valid := nativeOption(arg.Value, "Int", int64(0))
				if !valid {
					return Panic("PriorityQueue capacity must be positive")
				}
				q.capacity = int(value.(int64))
				if q.capacity <= 0 {
					if v, ok := arg.Value.(Alternative); !ok || v.Tag != "none" {
						return Panic("PriorityQueue capacity must be positive")
					}
				}
			}
		}
		return q
	case "@std/Synchronized":
		return &Synchronized{typ: typ, value: args[0].Value, changed: make(chan struct{})}
	case "@std/ListBuilder", "@std/MapBuilder", "@std/SetBuilder", "@std/BytesBuilder", "@std/StringBuilder":
		return newBuilder(typ)
	}
	return Construct(typ, args)
}

// Queue is a local mutable FIFO. Concurrent callers must protect every access
// with the same Synchronized acquisition, including reads and saved methods.
type Queue struct {
	typ      string
	capacity int // Zero means unbounded; explicitly supplied capacities must be positive.
	items    []Value
}

func (q *Queue) Operation(name string) Function {
	element := typeArguments(q.typ)[0]
	labels, result := []string{}, "@std/Optional["+element+"]"
	switch name {
	case "enqueue":
		labels, result = []string{"value"}, "Bool"
	case "length":
		result = "Int"
	case "is_empty":
		result = "Bool"
	case "dequeue", "peek":
	default:
		Panic("unknown Queue operation")
	}
	return NewFunction(labels, result, func(_ *Execution, args []Value) Value {
		switch name {
		case "enqueue":
			if q.capacity > 0 && len(q.items) == q.capacity {
				return false
			}
			q.items = append(q.items, args[0])
			return true
		case "length":
			return int64(len(q.items))
		case "is_empty":
			return len(q.items) == 0
		default:
			if len(q.items) == 0 {
				return optional(element, nil, false)
			}
			value := q.items[0]
			if name == "dequeue" {
				q.items[0] = nil
				q.items = q.items[1:]
				if len(q.items) == 0 {
					q.items = nil
				}
			}
			return optional(element, value, true)
		}
	})
}

type Builder struct {
	mu     sync.Mutex
	typ    string
	value  Value
	sealed bool
}

func newBuilder(typ string) *Builder {
	name, args := splitType(typ)
	b := &Builder{typ: typ}
	switch name {
	case "@std/ListBuilder":
		b.value = &List{"@std/List[" + args[0] + "]", nil}
	case "@std/MapBuilder":
		b.value = &Map{"@std/Map[" + args[0] + "][" + args[1] + "]", nil}
	case "@std/SetBuilder":
		b.value = &Set{"@std/Set[" + args[0] + "]", nil}
	case "@std/BytesBuilder":
		b.value = Bytes{}
	case "@std/StringBuilder":
		b.value = ""
	}
	return b
}
func (b *Builder) Operation(name string) Function {
	labels := []string{}
	if name == "append" || name == "with_value" {
		labels = []string{"value"}
	}
	if name == "with_entry" {
		labels = []string{"key", "value"}
	}
	if name == "concat" {
		labels = []string{"values"}
	}
	return NewFunction(labels, "", func(ctx *Execution, args []Value) Value {
		b.mu.Lock()
		defer b.mu.Unlock()
		if name == "freeze" {
			b.sealed = true
			return b.value
		}
		if b.sealed {
			return Panic("builder is sealed")
		}
		switch value := b.value.(type) {
		case *List:
			value.Items = append(value.Items, args[0])
			b.value = value
		case *Map, *Set:
			named := make([]Argument, len(args))
			for i, arg := range args {
				named[i] = Argument{labels[i], arg}
			}
			b.value = Invoke(ctx, NativeMember(value, name), named)
		case Bytes:
			if name == "concat" {
				value.Items = append(append([]byte{}, value.Items...), args[0].(Bytes).Items...)
			} else {
				n := args[0].(int64)
				if n < 0 || n > 255 {
					return Panic("byte value must be between 0 and 255")
				}
				value.Items = append(append([]byte{}, value.Items...), byte(n))
			}
			b.value = value
		case string:
			b.value = value + args[0].(string)
		}
		return Unit{}
	})
}
