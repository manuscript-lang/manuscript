package msruntime

import (
	"strings"
	"unicode/utf8"
)

// Each group's list is shared source-visible membership. Ordinary collection
// synchronization rules apply; reading headers does not copy list membership.
type libraryHeaders struct {
	Entries []Entry
	index   map[string]*List
}

func (h *libraryHeaders) values(name string) (*List, bool) {
	values, ok := h.index[httpHeaderKey(name)]
	return values, ok
}

func (h *libraryHeaders) append(name string, value Bytes) {
	key := httpHeaderKey(name)
	values, ok := h.index[key]
	if !ok {
		if h.index == nil {
			h.index = map[string]*List{}
		}
		values = &List{Type: "@std/List[@std/Bytes]"}
		h.index[key] = values
		h.Entries = append(h.Entries, Entry{name, values})
	}
	values.Items = append(values.Items, value)
}

func init() {
	libraryAdd("http", "headers", "HttpHeaders", nil, func(_ *Execution, _ string, _ []Value) Value { return &libraryHeaders{} })
	libraryAdd("http", "headers_append", libraryResult("Unit", "HttpError"), []LibraryParam{{"headers", "HttpHeaders"}, {"name", "String"}, {"value", "Bytes"}}, func(_ *Execution, result string, args []Value) Value {
		if !validHeaderName(args[1].(string)) {
			return libraryError(result, "InvalidInput", "")
		}
		args[0].(*libraryHeaders).append(args[1].(string), args[2].(Bytes))
		return libraryOK(result, Unit{})
	})
	libraryAdd("http", "headers_values", "Optional[List[Bytes]]", []LibraryParam{{"headers", "HttpHeaders"}, {"name", "String"}}, func(_ *Execution, _ string, args []Value) Value {
		values, present := args[0].(*libraryHeaders).values(args[1].(string))
		return optional("@std/List[@std/Bytes]", values, present)
	})
	libraryAdd("http", "headers_text", "Result[Optional[List[String]]][HttpError]", []LibraryParam{{"headers", "HttpHeaders"}, {"name", "String"}}, func(ctx *Execution, result string, args []Value) Value {
		values, present := args[0].(*libraryHeaders).values(args[1].(string))
		if !present {
			return libraryOK(result, optional("@std/List[String]", nil, false))
		}
		out := NewList("@std/List[String]", nil)
		for _, value := range values.Items {
			CheckCancelled(ctx)
			data := value.(Bytes).Items
			if !utf8.Valid(data) {
				return libraryError(result, "InvalidData", "")
			}
			out.Append(string(data))
		}
		return libraryOK(result, optional("@std/List[String]", out, true))
	})
	libraryAdd("http", "headers_names", "List[String]", []LibraryParam{{"headers", "HttpHeaders"}}, func(_ *Execution, _ string, args []Value) Value {
		out := NewList("@std/List[String]", nil)
		for _, entry := range args[0].(*libraryHeaders).Entries {
			out.Append(entry.Key)
		}
		return out
	})
	libraryAdd("http", "headers_clone", "HttpHeaders", []LibraryParam{{"headers", "HttpHeaders"}}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return args[0].(*libraryHeaders).clone()
	})
	libraryAdd("http", "headers_remove", "Bool", []LibraryParam{{"headers", "HttpHeaders"}, {"name", "String"}}, func(_ *Execution, _ string, args []Value) Value {
		h := args[0].(*libraryHeaders)
		key := httpHeaderKey(args[1].(string))
		if _, present := h.index[key]; !present {
			return false
		}
		delete(h.index, key)
		for i, entry := range h.Entries {
			if httpHeaderKey(entry.Key.(string)) == key {
				copy(h.Entries[i:], h.Entries[i+1:])
				last := len(h.Entries) - 1
				h.Entries[last] = Entry{}
				h.Entries = h.Entries[:last]
				break
			}
		}
		return true
	})
	libraryAdd("http", "client_response_metadata", "HttpResponseMetadata", []LibraryParam{{"response", "ClientResponse"}}, func(_ *Execution, _ string, args []Value) Value { return libraryResponseMetadata(args[0].(Record)) })
	libraryAdd("http", "method_text", "String", []LibraryParam{{"method", "HttpMethod"}}, func(_ *Execution, _ string, args []Value) Value { return libraryHTTPMethodText(args[0]) })
}

func libraryResponseMetadata(response Record) Value {
	return readField(response.Fields, "head")
}

var httpMethodNames = map[string]string{"Get": "GET", "Head": "HEAD", "Post": "POST", "Put": "PUT", "Patch": "PATCH", "Delete": "DELETE", "Connect": "CONNECT", "Options": "OPTIONS", "Trace": "TRACE"}

func libraryHTTPMethodText(value Value) string {
	method := value.(Alternative)
	if method.Tag == "Custom" {
		return method.Fields[0].(string)
	}
	return httpMethodNames[method.Tag]
}

func libraryHTTPMethod(text string) Alternative {
	for name, token := range httpMethodNames {
		if token == text {
			return Alternative{"@std/HttpMethod", name, nil}
		}
	}
	return Alternative{"@std/HttpMethod", "Custom", []Value{text}}
}

func validHeaderName(name string) bool {
	if name == "" {
		return false
	}
	for _, r := range name {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("!#$%&'*+-.^_`|~", r)) {
			return false
		}
	}
	return true
}

func httpHeaderKey(name string) string {
	for i := range len(name) {
		if name[i] >= 'A' && name[i] <= 'Z' {
			data := []byte(name)
			for j := i; j < len(data); j++ {
				if data[j] >= 'A' && data[j] <= 'Z' {
					data[j] += 'a' - 'A'
				}
			}
			return string(data)
		}
	}
	return name
}

// HTTP field names use ASCII folding, not Unicode case equivalence.
func httpHeaderNameEqual(left, right string) bool { return httpHeaderKey(left) == httpHeaderKey(right) }

func (h *libraryHeaders) clone() *libraryHeaders {
	out := &libraryHeaders{index: map[string]*List{}}
	for _, entry := range h.Entries {
		values := Clone(entry.Value).(*List)
		out.Entries = append(out.Entries, Entry{entry.Key, values})
		out.index[httpHeaderKey(entry.Key.(string))] = values
	}
	return out
}
