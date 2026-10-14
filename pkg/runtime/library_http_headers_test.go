package msruntime

import (
	"io"
	"net/http"
	"reflect"
	"testing"
	"time"
)

func TestHTTPHeaderValues(t *testing.T) {
	first := libraryStrings([]string{"", "first"})
	headers := &Map{Type: "@std/Map[String][@std/List[String]]", Entries: []Entry{
		{"x-test", first}, {"Other", libraryStrings([]string{"skip"})},
		{"X-Test", libraryStrings([]string{"second", "third"})},
		{"X-Empty", libraryStrings(nil)}, {"K", libraryStrings([]string{"ascii"})},
	}}
	for _, tc := range []struct {
		name    string
		want    []string
		present bool
	}{
		{"x-test", []string{"", "first", "second", "third"}, true},
		{"X-TEST", []string{"", "first", "second", "third"}, true},
		{"x-empty", []string{}, true}, {"absent", nil, false}, {"K", nil, false},
	} {
		got := libraryCall(t, "http/header_values", headers, tc.name)
		if got.Type != "@std/Optional[@std/List[String]]" || (got.Tag == "some") != tc.present {
			t.Fatalf("%q: %#v", tc.name, got)
		}
		if tc.present && !reflect.DeepEqual(libraryStringValues(got.Fields[0]), tc.want) {
			t.Fatalf("%q: %#v, want %q", tc.name, got, tc.want)
		}
	}
	got := libraryCall(t, "http/header_values", headers, "X-Test").Fields[0].(*List)
	got.Items[0] = "changed copy"
	first.Items[1] = "changed input"
	if got.Items[1] != "first" || first.Items[0] != "" || headers.Entries[0].Key != "x-test" || len(headers.Entries) != 5 {
		t.Fatal("helper shared membership or mutated keys", headers, got)
	}
}

func TestHTTPRequestHeader(t *testing.T) {
	headers := &Map{Type: "@std/Map[String][@std/Bytes]", Entries: []Entry{
		{"Content-Type", Bytes{[]byte("application/json")}},
		{"x-test", Bytes{[]byte("first\nsecond")}},
		{"X-Test", Bytes{[]byte("later")}},
		{"X-Empty", Bytes{}},
		{"K", Bytes{[]byte("ascii")}},
	}}
	request := Record{"@std/HttpRequest", map[string]Value{"headers": headers}}
	for _, tc := range []struct {
		name, want string
		present    bool
	}{
		{"content-type", "application/json", true},
		{"CONTENT-TYPE", "application/json", true},
		{"Content-Type", "application/json", true},
		{"X-TEST", "first\nsecond", true},
		{"x-empty", "", true},
		{"missing", "", false},
		{"K", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Invoke(RootExecution(), NativeMember(request, "header"), []Argument{{"name", tc.name}}).(Alternative)
			if got.Type != "@std/Optional[@std/Bytes]" || (got.Tag == "some") != tc.present {
				t.Fatalf("unexpected Optional: %#v", got)
			}
			if tc.present && string(got.Fields[0].(Bytes).Items) != tc.want {
				t.Fatalf("unexpected header bytes: %#v", got)
			}
		})
	}
	if headers.Entries[0].Key != "Content-Type" || len(headers.Entries) != 5 {
		t.Fatal("header lookup changed map keys")
	}
	if _, ok := nativeLibraryMember(Record{"local/HttpRequest", request.Fields}, "header", ""); ok {
		t.Fatal("unrelated record acquired standard header method")
	}
}

func TestHTTPReceivedHeaderValues(t *testing.T) {
	root := RootExecution()
	handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(ctx *Execution, args []Value) Value {
		request := args[0].(Record)
		headers := request.Fields["headers"].(*Map)
		for _, entry := range headers.Entries {
			if entry.Key == "x-test" {
				return hostResponse(500, "raw header key changed")
			}
		}
		value := Invoke(ctx, NativeMember(request, "header"), []Argument{{"name", "x-TEST"}}).(Alternative)
		if value.Tag != "some" {
			return hostResponse(500, "header missing")
		}
		return hostResponse(200, string(value.Fields[0].(Bytes).Items))
	})
	service := serveTest(t, root, handler, 1024)
	request, err := http.NewRequest("GET", "http://"+service.listener.Addr().String(), nil)
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Add("x-test", "first")
	request.Header.Add("X-Test", "second")
	client := &http.Client{Timeout: 2 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || response.StatusCode != 200 || string(body) != "first\nsecond" {
		t.Fatalf("received headers: status=%d body=%q err=%v", response.StatusCode, body, err)
	}
}
