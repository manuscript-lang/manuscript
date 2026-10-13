package msruntime

import (
	"strings"
	"unicode/utf8"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("io", "read_line", libraryResult("Optional[String]", "IoError"), []LibraryParam{p("input", "ReadStream"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[1].(int64)
		if max <= 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var b []byte
		for {
			v := Invoke(ctx, Bind(a[0], "", "read"), []Argument{{"max_bytes", optional("Int", int64(1), true)}}).(Alternative)
			if v.Tag == "error" {
				return Alternative{r, "error", v.Fields}
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
	libraryAdd("string", "repeat", libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("count", "Int"), p("max_bytes", "Optional[Int]")}, func(_ *Execution, r string, a []Value) Value {
		s := a[0].(string)
		count, max := a[1].(int64), a[2].(int64)
		if count < 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		if len(s) == 0 {
			return libraryOK(r, "")
		}
		max = min(max, nativeMaxBytes)
		if count > max/int64(len(s)) {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryOK(r, strings.Repeat(s, int(count)))
	})
	libraryAdd("regex", "replace", libraryResult("String", "RegexError"), []LibraryParam{p("pattern", "Regex"), p("text", "String"), p("replacement", "String"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
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
