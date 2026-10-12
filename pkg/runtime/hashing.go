package msruntime

import (
	"fmt"
	"hash/fnv"
	"sort"
	"strconv"
)

// Hashes are lookup aids, not a serialization format. Composite hashing uses
// the same explicit implementations as equality, including nested domain keys.
func HashIn(ctx *Execution, value Value) int64 {
	if view, ok := value.(View); ok {
		child := *ctx
		child.EqualityScope = view.Scope
		return HashIn(&child, view.Receiver)
	}
	if method, ok := implementationFunction(value, "@std/Hashable", "hash", ctx.EqualityScope); ok {
		return Invoke(ctx, method, nil).(int64)
	}
	h := fnv.New64a()
	write := func(s string) { h.Write([]byte(strconv.Itoa(len(s)) + ":" + s)) }
	switch v := value.(type) {
	case Record:
		write(v.Type)
		keys := make([]string, 0, len(v.Fields))
		for k := range v.Fields {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			write(k)
			write(strconv.FormatInt(HashIn(ctx, v.Fields[k]), 10))
		}
	case Alternative:
		write(v.Type)
		write(v.Tag)
		for _, field := range v.Fields {
			write(strconv.FormatInt(HashIn(ctx, field), 10))
		}
	case Decimal:
		write(v.Value.RatString())
	case Instant:
		write(fmt.Sprintf("%p", v.Domain))
		write(strconv.FormatInt(v.Tick, 10))
	default:
		write(Format(value))
	}
	return int64(h.Sum64())
}
