package msruntime

import (
	"io"
	"net/http"
	"reflect"
	"testing"
	"time"
)

// Fixtures use this explicit text/raw conversion rather than production support
// for legacy maps. Malformed native fields can exercise transport validation.
func httpTestHeaders(input *Map) *libraryHeaders {
	out := &libraryHeaders{}
	for _, entry := range input.Entries {
		name := entry.Key.(string)
		switch v := entry.Value.(type) {
		case string:
			out.append(name, Bytes{[]byte(v)})
		case Bytes:
			out.append(name, v)
		case *List:
			for _, value := range v.Items {
				switch v := value.(type) {
				case string:
					out.append(name, Bytes{[]byte(v)})
				case Bytes:
					out.append(name, v)
				}
			}
		}
	}
	return out
}
func httpTestTextValues(value Value) []string {
	out := []string{}
	for _, value := range value.(*List).Items {
		out = append(out, string(value.(Bytes).Items))
	}
	return out
}

func TestHTTPHeadersAliasingAndUTF8(t *testing.T) {
	headers := httpTestHeaders(&Map{Entries: []Entry{{"x-test", "first"}, {"Other", "skip"}, {"X-Test", "second"}, {"K", "ascii"}}})
	first, _ := headers.values("X-TEST")
	second, _ := headers.values("x-test")
	if first != second || !reflect.DeepEqual(httpTestTextValues(first), []string{"first", "second"}) {
		t.Fatal("lookup lost values or copied membership")
	}
	if _, ok := headers.values("K"); ok {
		t.Fatal("Unicode folding")
	}
	if _, ok := headers.values("absent"); ok {
		t.Fatal("absent header")
	}
	first.Items[0] = Bytes{[]byte("mutated")}
	headers.append("X-TEST", Bytes{})
	if first != second || !reflect.DeepEqual(httpTestTextValues(second), []string{"mutated", "second", ""}) {
		t.Fatal("append did not share membership")
	}
	clone := httpTestCall("http/headers_clone", headers).(*libraryHeaders)
	cloned, _ := clone.values("x-test")
	cloned.Items[0] = Bytes{[]byte("clone")}
	if string(first.Items[0].(Bytes).Items) != "mutated" {
		t.Fatal("clone shares membership")
	}
	first.Items = nil
	got := libraryCall(t, "http/headers_values", headers, "x-test")
	if got.Tag != "some" || len(got.Fields[0].(*List).Items) != 0 {
		t.Fatal("present empty list")
	}
	headers.append("Raw", Bytes{[]byte{255}})
	libraryFailure(t, libraryCall(t, "http/headers_text", headers, "raw"), "InvalidData")
	for _, name := range []string{"", "bad name", "bad:name", "é", "x\r\ny"} {
		libraryFailure(t, libraryCall(t, "http/headers_append", headers, name, Bytes{}), "InvalidInput")
	}
	names := httpTestCall("http/headers_names", headers).(*List)
	if !reflect.DeepEqual(libraryStringValues(names), []string{"x-test", "Other", "K", "Raw"}) {
		t.Fatal(names)
	}
}

func TestHTTPReceivedHeaderValues(t *testing.T) {
	root := RootExecution()
	handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, args []Value) Value {
		headers := args[0].(Record).Fields["headers"].(*libraryHeaders)
		values, ok := headers.values("x-TEST")
		if !ok || !reflect.DeepEqual(httpTestTextValues(values), []string{"first", "second"}) {
			return hostResponse(500, "header values lost")
		}
		return hostResponse(200, "ok")
	})
	service := serveTest(t, root, handler, 1024)
	request, err := http.NewRequest("GET", "http://"+service.listener.Addr().String(), nil)
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Add("x-test", "first")
	request.Header.Add("X-Test", "second")
	response, err := (&http.Client{Timeout: 2 * time.Second}).Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || response.StatusCode != 200 || string(body) != "ok" {
		t.Fatalf("%d %q %v", response.StatusCode, body, err)
	}
}

func httpTestCall(name string, a ...Value) Value {
	spec := libraryFunctions[name]
	return invokeLibrary(spec, RootExecution(), libraryRuntimeType(spec.Result), a)
}

func TestHTTPMetadataSnapshotSharesHeaders(t *testing.T) {
	headers := &libraryHeaders{}
	headers.append("X-Test", Bytes{[]byte("first")})
	response := Record{"@std/ClientResponse", map[string]Value{"status": int64(200), "headers": headers, "body": Bytes{}}}
	first := httpTestCall("http/client_response_metadata", response).(Record)
	first.Fields["status"] = int64(999)
	first.Fields["headers"].(*libraryHeaders).append("x-test", Bytes{[]byte("second")})
	next := httpTestCall("http/client_response_metadata", response).(Record)
	if next.Fields["status"] != int64(200) || next.Fields["headers"] != headers {
		t.Fatal("metadata snapshot or alias contract", next)
	}
	values, _ := headers.values("X-Test")
	if !reflect.DeepEqual(httpTestTextValues(values), []string{"first", "second"}) {
		t.Fatal("metadata copied membership")
	}
	if _, ok := nativeLibraryMember(Record{"local/ClientResponse", response.Fields}, "metadata", ""); ok {
		t.Fatal("local record acquired metadata")
	}
}
