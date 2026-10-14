package msruntime

import (
	"bytes"
	"encoding/hex"
	"unicode/utf8"
)

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	libraryAdd("bytes", "index_of_from", "Optional[Int]", []LibraryParam{p("data", "Bytes"), p("value", "Bytes"), p("start", "Int")}, func(ctx *Execution, _ string, a []Value) Value {
		CheckCancelled(ctx)
		data, value, start := a[0].(Bytes).Items, a[1].(Bytes).Items, a[2].(int64)
		if start < 0 || start > int64(len(data)) {
			return libraryRangeFault("Bytes.index_of_from", "start", start, 0, int64(len(data)))
		}
		index := bytes.Index(data[start:], value)
		CheckCancelled(ctx)
		return optional("Int", start+int64(index), index >= 0)
	})
	libraryAdd("bytes", "to_hex", "String", []LibraryParam{p("data", "Bytes")}, func(ctx *Execution, _ string, a []Value) Value {
		CheckCancelled(ctx)
		out := hex.EncodeToString(a[0].(Bytes).Items)
		CheckCancelled(ctx)
		return out
	})
	libraryAdd("regex", "find", "Optional[RegexMatch]", []LibraryParam{p("pattern", "Regex"), p("text", "String")}, libraryRegexFind)
	libraryAdd("regex", "split", libraryResult("List[String]", "RegexError"), []LibraryParam{p("pattern", "Regex"), p("text", "String"), p("max_parts", "Optional[Int]")}, libraryRegexSplit)
}

func libraryRegexFind(ctx *Execution, _ string, a []Value) Value {
	CheckCancelled(ctx)
	text := a[1].(string)
	indices := a[0].(libraryRegex).pattern.FindStringSubmatchIndex(text)
	CheckCancelled(ctx)
	if indices == nil {
		return optional("@std/RegexMatch", nil, false)
	}
	groups := make([]Value, len(indices)/2-1)
	for i := range groups {
		if i%1024 == 0 {
			CheckCancelled(ctx)
		}
		start, end := indices[2*i+2], indices[2*i+3]
		groups[i] = optional("String", nil, false)
		if start >= 0 {
			groups[i] = optional("String", text[start:end], true)
		}
	}
	start := libraryScalarPrefix(ctx, text, indices[0])
	end := start + libraryScalarPrefix(ctx, text[indices[0]:], indices[1]-indices[0])
	match := Record{Type: "@std/RegexMatch", Fields: map[string]Value{
		"text": text[indices[0]:indices[1]], "start": start, "end": end,
		"groups": libraryList("@std/Optional[String]", groups),
	}}
	return optional("@std/RegexMatch", match, true)
}

func libraryScalarPrefix(ctx *Execution, text string, end int) int64 {
	var count int64
	for i := 0; i < end; count++ {
		if count%1024 == 0 {
			CheckCancelled(ctx)
		}
		_, width := utf8.DecodeRuneInString(text[i:])
		i += width
	}
	return count
}

func libraryRegexSplit(ctx *Execution, result string, a []Value) Value {
	CheckCancelled(ctx)
	text, maximum := a[1].(string), a[2].(int64)
	if maximum < 0 {
		return libraryError(result, "InvalidInput", "")
	}
	if maximum == 0 {
		return libraryOK(result, libraryStrings(nil))
	}
	// At most one boundary per byte plus the final part. Saturating against
	// input size also prevents converting an unlimited Int into a host int.
	bound := min(maximum, int64(len(text))+1)
	pattern := a[0].(libraryRegex).pattern
	// Match Go's regexp.Split treatment of an empty pattern and empty input.
	if text == "" && pattern.String() != "" {
		return libraryOK(result, libraryStrings([]string{""}))
	}
	indices := pattern.FindAllStringIndex(text, int(min(bound+1, int64(len(text))+1)))
	CheckCancelled(ctx)
	parts := make([]string, 0, min(len(indices)+1, int(bound)))
	position, lastStart := 0, 0
	for i, index := range indices {
		if i%1024 == 0 {
			CheckCancelled(ctx)
		}
		if index[1] != 0 {
			parts = append(parts, text[position:index[0]])
			if int64(len(parts)) == maximum {
				return libraryOK(result, libraryStrings(parts))
			}
		}
		position, lastStart = index[1], index[0]
	}
	if lastStart != len(text) && int64(len(parts)) < maximum {
		parts = append(parts, text[position:])
	}
	return libraryOK(result, libraryStrings(parts))
}
