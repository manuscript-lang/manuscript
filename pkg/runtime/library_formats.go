package msruntime

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"html"
	"io"
	"net"
	"net/url"

	"strconv"
	"strings"
	"unicode/utf8"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	add := libraryAdd
	add("json", "parse", libraryResult("JsonValue", "JsonError"), []LibraryParam{p("text", "String"), p("limits", "Optional[JsonLimits]")}, libraryJSONParse)
	add("json", "stringify", libraryResult("String", "JsonError"), []LibraryParam{p("value", "JsonValue"), p("max_bytes", "Optional[Int]")}, libraryJSONStringify)
	add("csv", "parse", libraryResult("List[List[String]]", "CsvError"), []LibraryParam{p("text", "String"), p("options", "CsvOptions"), p("max_rows", "Optional[Int]"), p("max_cells", "Optional[Int]")}, libraryCSVParse)
	add("csv", "stringify", libraryResult("String", "CsvError"), []LibraryParam{p("rows", "List[List[String]]"), p("options", "CsvOptions"), p("max_bytes", "Optional[Int]")}, libraryCSVStringify)
	add("html", "escape", "String", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, a []Value) Value { return html.EscapeString(a[0].(string)) })
	add("html", "unescape", "String", []LibraryParam{p("text", "String")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		text := html.UnescapeString(args[0].(string))
		CheckCancelled(ctx)
		return text
	})
	add("url", "encode_component", "String", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, a []Value) Value {
		text := a[0].(string)
		var b strings.Builder
		const digits = "0123456789ABCDEF"
		for i := 0; i < len(text); i++ {
			v := text[i]
			if v >= 'A' && v <= 'Z' || v >= 'a' && v <= 'z' || v >= '0' && v <= '9' || strings.ContainsRune("-._~", rune(v)) {
				b.WriteByte(v)
			} else {
				b.WriteByte('%')
				b.WriteByte(digits[v>>4])
				b.WriteByte(digits[v&15])
			}
		}
		return b.String()
	})
	add("url", "decode_component", libraryResult("String", "UrlError"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		s, err := url.PathUnescape(a[0].(string))
		if err != nil || !utf8.ValidString(s) {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, s)
	})
	add("url", "parse", libraryResult("Url", "UrlError"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		u, err := url.Parse(a[0].(string))
		if err != nil || u.Scheme == "" || u.User != nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryURLValue(r, u)
	})
	add("url", "resolve", libraryResult("Url", "UrlError"), []LibraryParam{p("base", "Url"), p("reference", "String")}, func(_ *Execution, r string, a []Value) Value {
		base, err := libraryURL(a[0])
		if err != nil {
			return libraryError(r, "InvalidInput", "")
		}
		u, err := url.Parse(a[1].(string))
		if err != nil || u.User != nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryURLValue(r, base.ResolveReference(u))
	})
	add("url", "format", libraryResult("String", "UrlError"), []LibraryParam{p("value", "Url")}, func(_ *Execution, r string, a []Value) Value {
		u, err := libraryURL(a[0])
		if err != nil {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, u.String())
	})
	add("url", "parse_query", libraryResult("List[QueryEntry]", "UrlError"), []LibraryParam{p("text", "String"), p("max_entries", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		n := a[1].(int64)
		if n < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		s := a[0].(string)
		var items []Value
		if s != "" {
			for _, part := range strings.Split(s, "&") {
				CheckCancelled(ctx)
				if int64(len(items)) >= n {
					return libraryError(r, "LimitExceeded", "")
				}
				k, v, _ := strings.Cut(part, "=")
				k, e1 := url.QueryUnescape(k)
				v, e2 := url.QueryUnescape(v)
				if e1 != nil || e2 != nil || !utf8.ValidString(k) || !utf8.ValidString(v) {
					return libraryError(r, "InvalidData", "")
				}
				items = append(items, Record{"@std/QueryEntry", map[string]Value{"key": k, "value": v}})
			}
		}
		return libraryOK(r, libraryList("@std/QueryEntry", items))
	})
	add("url", "format_query", "String", []LibraryParam{p("entries", "List[QueryEntry]")}, func(_ *Execution, _ string, a []Value) Value {
		parts := make([]string, len(a[0].(*List).Items))
		for i, v := range a[0].(*List).Items {
			f := v.(Record).Fields
			parts[i] = url.QueryEscape(f["key"].(string)) + "=" + url.QueryEscape(f["value"].(string))
		}
		return strings.Join(parts, "&")
	})
	add("net", "parse_ip", libraryResult("String", "NetworkError"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		ip := net.ParseIP(a[0].(string))
		if ip == nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, ip.String())
	})
}

// Parsing uses tokens to retain exact numbers and reject duplicate object keys.
func libraryJSONParse(ctx *Execution, r string, a []Value) Value {
	text := a[0].(string)
	f := a[1].(Record).Fields
	maxBytes, maxDepth, maxValues := f["max_bytes"].(int64), f["max_depth"].(int64), f["max_values"].(int64)
	if maxBytes < 0 || maxDepth < 0 || maxValues < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	if int64(len(text)) > maxBytes {
		return libraryError(r, "LimitExceeded", "")
	}
	// Go's decoder replaces unpaired surrogate escapes; reject them before decoding.
	if !libraryJSONUnicode(ctx, text) {
		return libraryError(r, "InvalidData", "")
	}
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	count := int64(0)
	code := "InvalidData"
	var parse func(int64) (Value, error)
	parse = func(depth int64) (Value, error) {
		CheckCancelled(ctx)
		count++
		if count > maxValues {
			code = "LimitExceeded"
			return nil, io.ErrShortBuffer
		}
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		alt := func(tag string, fields ...Value) Value { return Alternative{"@std/JsonValue", tag, fields} }
		switch v := token.(type) {
		case nil:
			return alt("Null"), nil
		case bool:
			return alt("BoolValue", v), nil
		case string:
			return alt("StringValue", v), nil
		case json.Number:
			return alt("NumberValue", string(v)), nil
		case json.Delim:
			if depth+1 > maxDepth {
				code = "LimitExceeded"
				return nil, io.ErrShortBuffer
			}
			if v == '[' {
				var items []Value
				for decoder.More() {
					item, err := parse(depth + 1)
					if err != nil {
						return nil, err
					}
					items = append(items, item)
				}
				end, err := decoder.Token()
				if err != nil || end != json.Delim(']') {
					return nil, io.ErrUnexpectedEOF
				}
				return alt("ArrayValue", libraryList("@std/JsonValue", items)), nil
			}
			if v == '{' {
				m := &Map{Type: "@std/Map[String][@std/JsonValue]"}
				seen := map[string]bool{}
				for decoder.More() {
					key, err := decoder.Token()
					if err != nil {
						return nil, err
					}
					s, ok := key.(string)
					if !ok || seen[s] {
						return nil, io.ErrUnexpectedEOF
					}
					seen[s] = true
					value, err := parse(depth + 1)
					if err != nil {
						return nil, err
					}
					m.Entries = append(m.Entries, Entry{s, value})
				}
				end, err := decoder.Token()
				if err != nil || end != json.Delim('}') {
					return nil, io.ErrUnexpectedEOF
				}
				return alt("ObjectValue", m), nil
			}
		}
		return nil, io.ErrUnexpectedEOF
	}
	value, err := parse(0)
	if err != nil {
		return libraryError(r, code, "")
	}
	if _, err := decoder.Token(); err != io.EOF {
		return libraryError(r, "InvalidData", "")
	}
	return libraryOK(r, value)
}
func libraryJSONUnicode(ctx *Execution, s string) bool {
	inString := false
	for i := 0; i < len(s); i++ {
		if i%4096 == 0 {
			CheckCancelled(ctx)
		}
		if s[i] == '"' {
			inString = !inString
			continue
		}
		if !inString || s[i] != '\\' {
			continue
		}
		i++
		if i >= len(s) {
			return false
		}
		if s[i] != 'u' {
			continue
		}
		if i+4 >= len(s) {
			return false
		}
		v, err := strconv.ParseUint(s[i+1:i+5], 16, 16)
		if err != nil {
			return false
		}
		i += 4
		if v >= 0xDC00 && v <= 0xDFFF {
			return false
		}
		if v >= 0xD800 && v <= 0xDBFF {
			if i+6 >= len(s) || s[i+1:i+3] != "\\u" {
				return false
			}
			lo, err := strconv.ParseUint(s[i+3:i+7], 16, 16)
			if err != nil || lo < 0xDC00 || lo > 0xDFFF {
				return false
			}
			i += 6
		}
	}
	return true
}

type libraryLimitedWriter struct {
	bytes.Buffer
	max      int64
	overflow bool
}

func (w *libraryLimitedWriter) Write(p []byte) (int, error) {
	if int64(len(p)) > w.max-int64(w.Len()) {
		w.overflow = true
		return 0, io.ErrShortBuffer
	}
	return w.Buffer.Write(p)
}
func libraryJSONStringify(ctx *Execution, r string, a []Value) Value {
	max := a[1].(int64)
	if max < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	w := &libraryLimitedWriter{max: max}
	code := "InvalidData"
	active := map[equalityIdentity]bool{}
	var emit func(Value, int) error
	write := func(s string) error { _, err := w.Write([]byte(s)); return err }
	emit = func(value Value, depth int) error {
		CheckCancelled(ctx)
		v := value.(Alternative)
		if v.Tag == "ArrayValue" || v.Tag == "ObjectValue" {
			identity, _ := equalityID(v.Fields[0])
			if active[identity] {
				return io.ErrUnexpectedEOF
			}
			active[identity] = true
			defer delete(active, identity)
		}
		switch v.Tag {
		case "Null":
			return write("null")
		case "BoolValue":
			return write(strconv.FormatBool(v.Fields[0].(bool)))
		case "StringValue":
			text := v.Fields[0].(string)
			if int64(len(text)) > w.max-int64(w.Len()) {
				w.overflow = true
				return io.ErrShortBuffer
			}
			b, _ := json.Marshal(text)
			_, err := w.Write(b)
			return err
		case "NumberValue":
			s := v.Fields[0].(string)
			if !json.Valid([]byte(s)) || s == "" || s[0] != '-' && (s[0] < '0' || s[0] > '9') {
				return io.ErrUnexpectedEOF
			}
			return write(s)
		case "ArrayValue":
			if err := write("["); err != nil {
				return err
			}
			for i, x := range v.Fields[0].(*List).Items {
				if i > 0 {
					if err := write(","); err != nil {
						return err
					}
				}
				if err := emit(x, depth+1); err != nil {
					return err
				}
			}
			return write("]")
		case "ObjectValue":
			if err := write("{"); err != nil {
				return err
			}
			for i, e := range v.Fields[0].(*Map).Entries {
				if i > 0 {
					if err := write(","); err != nil {
						return err
					}
				}
				key, _ := json.Marshal(e.Key.(string))
				if _, err := w.Write(key); err != nil {
					return err
				}
				if err := write(":"); err != nil {
					return err
				}
				if err := emit(e.Value, depth+1); err != nil {
					return err
				}
			}
			return write("}")
		}
		return io.ErrUnexpectedEOF
	}
	if err := emit(a[0], 0); err != nil {
		if w.overflow {
			code = "LimitExceeded"
		}
		return libraryError(r, code, "")
	}
	return libraryOK(r, w.String())
}
func libraryCSVOptions(v Value) (rune, bool, bool) {
	f := v.(Record).Fields
	s := f["delimiter"].(string)
	ending := f["line_ending"].(string)
	if len(s) != 1 || s[0] >= 128 || strings.ContainsAny(s, "\"\r\n\x00") || ending != "\n" && ending != "\r\n" {
		return 0, false, false
	}
	return rune(s[0]), ending == "\r\n", true
}
func libraryCSVParse(ctx *Execution, r string, a []Value) Value {
	delimiter, _, ok := libraryCSVOptions(a[1])
	rows, cells := a[2].(int64), a[3].(int64)
	if !ok || rows < 0 || cells < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	reader := csv.NewReader(strings.NewReader(a[0].(string)))
	reader.Comma = delimiter
	reader.FieldsPerRecord = -1
	var values []Value
	count := int64(0)
	for {
		CheckCancelled(ctx)
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return libraryError(r, "InvalidData", "")
		}
		if int64(len(values)) >= rows || int64(len(record)) > cells-count {
			return libraryError(r, "LimitExceeded", "")
		}
		count += int64(len(record))
		values = append(values, libraryStrings(record))
	}
	return libraryOK(r, libraryList("@std/List[String]", values))
}
func libraryCSVStringify(ctx *Execution, r string, a []Value) Value {
	delimiter, crlf, ok := libraryCSVOptions(a[1])
	n := a[2].(int64)
	if !ok || n < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	w := &libraryLimitedWriter{max: n}
	writer := csv.NewWriter(w)
	writer.Comma = delimiter
	writer.UseCRLF = crlf
	for _, row := range a[0].(*List).Items {
		CheckCancelled(ctx)
		record := libraryStringValues(row)
		// encoding/csv emits a bare line ending for a sole empty field,
		// which its reader skips. Quote it to retain this row on round trip.
		if len(record) == 1 && record[0] == "" {
			text := "\"\"\n"
			if crlf {
				text = "\"\"\r\n"
			}
			if _, err := w.Write([]byte(text)); err != nil {
				return libraryError(r, "LimitExceeded", "")
			}
			continue
		}
		if err := writer.Write(record); err != nil {
			return libraryError(r, "LimitExceeded", "")
		}
		writer.Flush()
		if writer.Error() != nil {
			return libraryError(r, "LimitExceeded", "")
		}
	}
	return libraryOK(r, w.String())
}
func libraryURLValue(r string, u *url.URL) Value {
	port := optional("Int", nil, false)
	if u.User != nil || u.Opaque != "" || u.Scheme == "" {
		return libraryError(r, "InvalidData", "")
	}
	if s := u.Port(); s != "" {
		n, err := strconv.ParseInt(s, 10, 64)
		if err != nil || n < 0 || n > 65535 {
			return libraryError(r, "InvalidData", "")
		}
		port = optional("Int", n, true)
	}
	if !utf8.ValidString(u.Path) || !utf8.ValidString(u.Fragment) {
		return libraryError(r, "InvalidData", "")
	}
	return libraryOK(r, Record{"@std/Url", map[string]Value{"scheme": strings.ToLower(u.Scheme), "host": strings.ToLower(u.Hostname()), "port": port, "path": u.EscapedPath(), "query": u.RawQuery, "fragment": u.Fragment}})
}
func libraryURL(v Value) (*url.URL, error) {
	f := v.(Record).Fields
	host := f["host"].(string)
	if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	p := f["port"].(Alternative)
	if p.Tag == "some" {
		n := p.Fields[0].(int64)
		if n < 0 || n > 65535 {
			return nil, io.ErrUnexpectedEOF
		}
		host = net.JoinHostPort(f["host"].(string), strconv.FormatInt(n, 10))
	}
	raw := f["path"].(string)
	decoded, err := url.PathUnescape(raw)
	if err != nil || !utf8.ValidString(decoded) {
		return nil, io.ErrUnexpectedEOF
	}
	u := &url.URL{Scheme: f["scheme"].(string), Host: host, Path: decoded, RawPath: raw, RawQuery: f["query"].(string), Fragment: f["fragment"].(string)}
	parsed, err := url.Parse(u.String())
	if err != nil || parsed.Scheme == "" || parsed.User != nil || strings.ContainsAny(host, "/@\\\r\n") {
		return nil, io.ErrUnexpectedEOF
	}
	return u, nil
}
