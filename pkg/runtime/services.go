package msruntime

import (
	"strings"
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
			return libraryRangeFault("Queue", "capacity", args[0].Value, 1, int64(^uint(0)>>1))
		}
		capacity := value.(int64)
		if option, ok := args[0].Value.(Alternative); ok && option.Tag == "none" {
			return &Queue{typ: typ}
		}
		if capacity <= 0 || capacity > int64(^uint(0)>>1) {
			return libraryRangeFault("Queue", "capacity", args[0].Value, 1, int64(^uint(0)>>1))
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
					return libraryRangeFault("PriorityQueue", "capacity", arg.Value, 1, int64(^uint(0)>>1))
				}
				q.capacity = int(value.(int64))
				if q.capacity <= 0 {
					if v, ok := arg.Value.(Alternative); !ok || v.Tag != "none" {
						return libraryRangeFault("PriorityQueue", "capacity", arg.Value, 1, int64(^uint(0)>>1))
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
	text   strings.Builder
	bytes  []byte
	sealed bool
}

func newBuilder(typ string) *Builder {
	name, args := splitType(typ)
	b := &Builder{typ: typ}
	switch name {
	case "@std/ListBuilder":
		b.value = NewList("@std/List["+args[0]+"]", nil)
	case "@std/MapBuilder":
		b.value = &Map{Type: "@std/Map[" + args[0] + "][" + args[1] + "]"}
	case "@std/SetBuilder":
		b.value = &Set{Type: "@std/Set[" + args[0] + "]"}
	case "@std/BytesBuilder":
		b.value = Bytes{}
	case "@std/StringBuilder":
		b.value = ""
	}
	return b
}
func (b *Builder) Operation(name string) Function {
	// Builder verbs retain the established Unit ABI and the same sealing lock.
	labels := []string{}
	if name == "append" || name == "add" {
		labels = []string{"value"}
	}
	if receiver, _ := splitType(b.typ); name == "add" && receiver == "@std/MapBuilder" {
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
			switch b.value.(type) {
			case Bytes:
				b.value = Bytes{Items: b.bytes}
			case string:
				b.value = b.text.String()
			}
			return b.value
		}
		if b.sealed {
			return Panic("builder is sealed")
		}
		switch value := b.value.(type) {
		case *List:
			value.Append(args[0])
			b.value = value
		case *Map, *Set:
			named := make([]Argument, len(args))
			for i, arg := range args {
				named[i] = Argument{labels[i], arg}
			}
			b.value = Invoke(ctx, NativeMember(value, name), named)
		case Bytes:
			if name == "concat" {
				b.bytes = append(b.bytes, args[0].(Bytes).Items...)
			} else {
				n := args[0].(int64)
				if n < 0 || n > 255 {
					return libraryRangeFault("BytesBuilder.append", "value", n, 0, 255)
				}
				b.bytes = append(b.bytes, byte(n))
			}
		case string:
			b.text.WriteString(args[0].(string))
		}
		return Unit{}
	})
}
