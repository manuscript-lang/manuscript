package msruntime

import (
	"encoding/binary"
	"sync"
)

// libraryRandom's sequence is part of the public reproducibility contract.
// Draws synchronize native state; reproducible ordering requires serialized calls.
type libraryRandom struct {
	mu    sync.Mutex
	state uint64
}

func init() { installRandomParity() }

func installRandomParity() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	variables := []LibraryParam{p("T", "")}
	libraryAdd("random", "secure_float", libraryResult("Float", "RandomError"), []LibraryParam{p("entropy", "Entropy")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		value := Invoke(ctx, Bind(args[0], "", "bytes"), []Argument{{"count", int64(8)}}).(Alternative)
		if value.Tag == "error" {
			return Alternative{result, "error", value.Fields}
		}
		data := value.Fields[0].(Bytes).Items
		if len(data) != 8 {
			return libraryError(result, "Failed", "entropy source must return exactly the requested 8 bytes")
		}
		return libraryOK(result, randomFloat(binary.BigEndian.Uint64(data)))
	})
	libraryGeneric("random", "secure_choice", libraryResult("Optional[T]", "RandomError"), variables, []LibraryParam{p("entropy", "Entropy"), p("values", "List[T]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := args[1].(*List).Items
		optionalType := typeArguments(result)[0]
		if len(items) == 0 {
			return libraryOK(result, Alternative{Type: optionalType, Tag: "none"})
		}
		index := librarySecureIndex(ctx, args[0], len(items))
		if index.Tag == "error" {
			return Alternative{result, "error", index.Fields}
		}
		return libraryOK(result, Alternative{optionalType, "some", []Value{items[index.Fields[0].(int64)]}})
	})
	libraryGeneric("random", "secure_shuffle", libraryResult("List[T]", "RandomError"), variables, []LibraryParam{p("entropy", "Entropy"), p("values", "List[T]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		out := randomListCopy(ctx, args[1].(*List), typeArguments(result)[0])
		for i := len(out.Items) - 1; i > 0; i-- {
			CheckCancelled(ctx)
			index := librarySecureIndex(ctx, args[0], i+1)
			if index.Tag == "error" {
				return Alternative{result, "error", index.Fields}
			}
			j := int(index.Fields[0].(int64))
			out.Items[i], out.Items[j] = out.Items[j], out.Items[i]
		}
		return libraryOK(result, out)
	})
	libraryAdd("random", "seeded", "Random", []LibraryParam{p("seed", "Int")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return &libraryRandom{state: uint64(args[0].(int64))}
	})
	libraryAdd("random", "int", libraryResult("Int", "RandomError"), []LibraryParam{p("random", "Random"), p("min", "Int"), p("max_exclusive", "Optional[Int]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		min, max := args[1].(int64), args[2].(int64)
		if min >= max {
			return libraryError(result, "InvalidInput", "")
		}
		width := uint64(max) - uint64(min)
		value := args[0].(*libraryRandom).bounded(ctx, width)
		return libraryOK(result, int64(uint64(min)+value))
	})
	libraryAdd("random", "float", "Float", []LibraryParam{p("random", "Random")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return randomFloat(args[0].(*libraryRandom).next())
	})
	libraryGeneric("random", "choice", "Optional[T]", variables, []LibraryParam{p("random", "Random"), p("values", "List[T]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := args[1].(*List).Items
		if len(items) == 0 {
			return Alternative{Type: result, Tag: "none"}
		}
		index := args[0].(*libraryRandom).bounded(ctx, uint64(len(items)))
		return Alternative{result, "some", []Value{items[index]}}
	})
	libraryGeneric("random", "shuffle", "List[T]", variables, []LibraryParam{p("random", "Random"), p("values", "List[T]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		out := randomListCopy(ctx, args[1].(*List), result)
		random := args[0].(*libraryRandom)
		for i := len(out.Items) - 1; i > 0; i-- {
			j := int(random.bounded(ctx, uint64(i+1)))
			out.Items[i], out.Items[j] = out.Items[j], out.Items[i]
		}
		return out
	})
}

func librarySecureIndex(ctx *Execution, entropy Value, length int) Alternative {
	return libraryFunctions["random/secure_int"].Body(ctx, "@std/Result[Int][@std/RandomError]", []Value{entropy, int64(0), int64(length)}).(Alternative)
}

func randomListCopy(ctx *Execution, values *List, typ string) *List {
	items := values.Items
	out := &List{Type: typ, Items: make([]Value, len(items))}
	for i, value := range items {
		CheckCancelled(ctx)
		out.Items[i] = value
	}
	return out
}

func randomFloat(word uint64) float64 { return float64(word>>11) * (1.0 / (1 << 53)) }

func (random *libraryRandom) next() uint64 {
	random.mu.Lock()
	defer random.mu.Unlock()
	random.state += 0x9e3779b97f4a7c15
	word := random.state
	word = (word ^ (word >> 30)) * 0xbf58476d1ce4e5b9
	word = (word ^ (word >> 27)) * 0x94d049bb133111eb
	return word ^ (word >> 31)
}

func (random *libraryRandom) bounded(ctx *Execution, width uint64) uint64 {
	// Reject the incomplete residue cycle so every result has equal probability.
	threshold := -width % width
	for {
		CheckCancelled(ctx)
		word := random.next()
		if word >= threshold {
			return word % width
		}
	}
}
