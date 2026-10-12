package msruntime

import (
	"encoding/json"
	"strings"
	"unicode/utf8"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("log", "write", libraryResult("Unit"), []LibraryParam{p("output", "WriteStream&Shareable"), p("level", "String"), p("message", "String"), p("fields", "Map[String][String]"), p("max_bytes", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		level := a[1].(string)
		if level != "debug" && level != "info" && level != "warn" && level != "error" || a[4].(int64) < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		m := map[string]string{}
		for _, e := range a[3].(Map).Entries {
			m[e.Key.(string)] = e.Value.(string)
		}
		data, err := json.Marshal(struct {
			Level   string            `json:"level"`
			Message string            `json:"message"`
			Fields  map[string]string `json:"fields"`
		}{level, a[2].(string), m})
		if err != nil {
			return libraryError(r, "InvalidData", "")
		}
		if int64(len(data)) >= a[4].(int64) {
			return libraryError(r, "LimitExceeded", "")
		}
		data = append(data, '\n')
		v := Invoke(ctx, Bind(a[0], "", "write"), []Argument{{"data", Bytes{data}}}).(Alternative)
		if v.Tag == "error" {
			return libraryError(r, "Failed", "log sink write failed")
		}
		return libraryOK(r, Unit{})
	})
	libraryAdd("io", "read_line", libraryResult("Optional[String]"), []LibraryParam{p("input", "ReadStream&Shareable"), p("max_bytes", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[1].(int64)
		if max <= 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var b []byte
		for {
			v := Invoke(ctx, Bind(a[0], "", "read"), []Argument{{"max_bytes", int64(1)}}).(Alternative)
			if v.Tag == "error" {
				return libraryError(r, "Failed", "line read failed")
			}
			part := v.Fields[0].(Alternative)
			if part.Tag == "none" {
				if len(b) == 0 {
					return libraryOK(r, optional("String", nil, false))
				}
				break
			}
			data := part.Fields[0].(Bytes).Items
			if len(data) != 1 {
				return libraryError(r, "Failed", "invalid stream chunk")
			}
			if int64(len(b)) >= max {
				return libraryError(r, "LimitExceeded", "")
			}
			b = append(b, data[0])
			if data[0] == '\n' {
				b = b[:len(b)-1]
				if len(b) > 0 && b[len(b)-1] == '\r' {
					b = b[:len(b)-1]
				}
				break
			}
		}
		if !libraryValidText(b) {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, optional("String", string(b), true))
	})
	libraryAdd("text", "repeat", libraryResult("String"), []LibraryParam{p("text", "String"), p("count", "Int"), p("max_bytes", "Int")}, func(_ *Execution, r string, a []Value) Value {
		s := a[0].(string)
		count, max := a[1].(int64), a[2].(int64)
		if count < 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		if len(s) == 0 {
			return libraryOK(r, "")
		}
		if count > max/int64(len(s)) || count > int64(^uint(0)>>1) {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryOK(r, strings.Repeat(s, int(count)))
	})
	libraryAdd("regex", "replace", libraryResult("String"), []LibraryParam{p("pattern", "Regex"), p("text", "String"), p("replacement", "String"), p("max_bytes", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[3].(int64)
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		text, replacement := a[1].(string), a[2].(string)
		indexes := a[0].(libraryRegex).pattern.FindAllStringIndex(text, -1)
		var out strings.Builder
		at := 0
		for _, index := range indexes {
			CheckCancelled(ctx)
			if int64(len(text[at:index[0]])) > max-int64(out.Len()) {
				return libraryError(r, "LimitExceeded", "")
			}
			out.WriteString(text[at:index[0]])
			if int64(len(replacement)) > max-int64(out.Len()) {
				return libraryError(r, "LimitExceeded", "")
			}
			out.WriteString(replacement)
			at = index[1]
		}
		if int64(len(text)-at) > max-int64(out.Len()) {
			return libraryError(r, "LimitExceeded", "")
		}
		out.WriteString(text[at:])
		return libraryOK(r, out.String())
	})
}

func libraryValidText(b []byte) bool { return utf8.Valid(b) }
