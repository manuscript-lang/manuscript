package msruntime

import (
	"github.com/gorilla/websocket"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestOptionalLimits(t *testing.T) {
	ctx := RootExecution()
	call := func(name string, args ...Argument) Value {
		spec := libraryFunctions[name]
		return Invoke(ctx, StandardFunction(name, libraryRuntimeType(spec.Result)), args)
	}
	if librarySuccess(t, call("string/repeat", Argument{"text", "ab"}, Argument{"count", int32(3)})) != "ababab" {
		t.Fatal("omitted cap")
	}
	libraryFailure(t, call("string/repeat", Argument{"text", "ab"}, Argument{"count", int32(3)}, Argument{"max_bytes", optional("Int", int32(5), true)}), "LimitExceeded")
	libraryFailure(t, call("string/repeat", Argument{"text", "a"}, Argument{"count", int32(1)}, Argument{"max_bytes", optional("Int", int32(0), true)}), "LimitExceeded")
	libraryFailure(t, call("string/repeat", Argument{"text", "a"}, Argument{"count", int32(1)}, Argument{"max_bytes", optional("Int", int32(-1), true)}), "InvalidInput")
	librarySuccess(t, call("json/parse", Argument{"text", "[1,2,3]"}))
	limits := Construct("@std/JsonLimits", nil)
	librarySuccess(t, call("json/parse", Argument{"text", "[1,2,3]"}, Argument{"limits", optional("@std/JsonLimits", limits, true)}))
	if !Equal(call("string/split", Argument{"text", "a,b,c"}, Argument{"separator", ","}, Argument{"max_parts", optional("Int", int32(2), true)}), libraryStrings([]string{"a", "b"})) {
		t.Fatal("JS split cap")
	}
	if call("string/replace", Argument{"text", "aba"}, Argument{"old", "a"}, Argument{"new", "x"}) != "xba" {
		t.Fatal("replace must replace one match by default")
	}
}
func TestJavascriptRound(t *testing.T) {
	for _, v := range []struct{ input, want float32 }{{-1.5, -1}, {-2.5, -2}, {1.5, 2}, {2.5, 3}, {math.Nextafter32(0.5, 0), 0}} {
		if got := float32(javascriptRound(float64(v.input))); got != v.want {
			t.Fatalf("round(%v)=%v", v.input, got)
		}
	}
	if got := javascriptRound(-0.5); got != 0 || !math.Signbit(got) {
		t.Fatal("negative zero lost")
	}
}
func TestPriorityQueueOrderingAndFaultRecovery(t *testing.T) {
	ctx := RootExecution()
	compare := NewFunction([]string{"left", "right"}, "Int", func(_ *Execution, a []Value) Value { return a[0].(int32) - a[1].(int32) })
	q := ConstructWithContext(ctx, "@std/PriorityQueue[Int]", []Argument{{"compare", compare}}).(*PriorityQueue)
	for _, v := range []int32{8, 2, 5, 1, 3, 7, 6, 4} {
		Invoke(ctx, q.Operation("enqueue"), []Argument{{"value", v}})
	}
	for want := int32(1); want <= 8; want++ {
		got := Invoke(ctx, q.Operation("dequeue"), nil).(Alternative)
		if got.Tag != "some" || got.Fields[0] != want {
			t.Fatal(want, got)
		}
	}
	if Invoke(ctx, q.Operation("peek"), nil).(Alternative).Tag != "none" {
		t.Fatal("empty heap")
	}
	Invoke(ctx, q.Operation("enqueue"), []Argument{{"value", int32(2)}})
	q.compare = NewFunction([]string{"left", "right"}, "Int", func(_ *Execution, _ []Value) Value { return Panic("bad comparison") })
	if recovered(func() { Invoke(ctx, q.Operation("enqueue"), []Argument{{"value", int32(1)}}) }) == nil || len(q.items) != 1 {
		t.Fatal("comparison fault corrupted queue")
	}
}
func TestSchedulerCombinedLifecycle(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(ctx, nil).(*Scheduler)
	var calls atomic.Int64
	operation := NewFunction(nil, "@std/Result[Unit][String]", func(_ *Execution, _ []Value) Value {
		calls.Add(1)
		return libraryOK("@std/Result[Unit][String]", Unit{})
	})
	libraryFailure(t, s.schedule(ctx, 0, true, operation), "InvalidInput")
	id := librarySuccess(t, s.schedule(ctx, 0, false, operation)).(OperationId)
	awaitStatus := func(id OperationId, want string) {
		t.Helper()
		deadline := time.Now().Add(time.Second)
		for s.Operation("status").Body(ctx, []Value{id}).(Alternative).Tag != want {
			if time.Now().After(deadline) {
				t.Fatal("status never reached", want)
			}
			time.Sleep(time.Millisecond)
		}
	}
	awaitStatus(id, "Succeeded")
	replacement := librarySuccess(t, s.restart(ctx, id)).(OperationId)
	awaitStatus(replacement, "Succeeded")
	if replacement == id || calls.Load() != 2 {
		t.Fatal("restart identity/completion")
	}
	for i := 0; i < 200; i++ {
		librarySuccess(t, s.schedule(ctx, Duration(time.Hour), false, operation))
	}
	s.close(ctx)
	if len(s.active) != 0 {
		t.Fatal("shutdown did not join scheduled work")
	}
	libraryFailure(t, s.schedule(ctx, 0, false, operation), "Closed")
}
func TestSchedulerShutdownJoinsCallbackAndReportsFailure(t *testing.T) {
	ctx := RootExecution()
	s := NewScheduler(ctx, nil).(*Scheduler)
	entered, finished := make(chan struct{}), make(chan struct{})
	operation := NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		close(entered)
		defer close(finished)
		<-child.Context.Done()
		CheckCancelled(child)
		return Unit{}
	})
	id := librarySuccess(t, s.schedule(ctx, 0, false, operation)).(OperationId)
	<-entered
	s.close(ctx)
	select {
	case <-finished:
	default:
		t.Fatal("callback not joined")
	}
	if s.Operation("status").Body(ctx, []Value{id}).(Alternative).Tag != "Cancelled" {
		t.Fatal("cancelled status")
	}
}

func TestOmittedQueueCapacityIsUnbounded(t *testing.T) {
	ctx := RootExecution()
	q := ConstructWithContext(ctx, "@std/Queue[Int]", []Argument{{"capacity", optional("Int", nil, false)}}).(*Queue)
	if q.capacity != 0 {
		t.Fatal("none imposed a capacity")
	}
}

func TestNetworkOptionalDeadlinesAndBudgets(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(Shield(ctx), nil)
	listener := librarySuccess(t, Invoke(ctx, n.Operation("listen"), []Argument{{"address", "127.0.0.1:0"}}))
	defer Invoke(Shield(ctx), Bind(listener, "", "close"), nil)
	address := Invoke(ctx, Bind(listener, "", "address"), nil)
	connected := make(chan Value, 1)
	go func() { connected <- Invoke(ctx, n.Operation("connect"), []Argument{{"address", address}}) }()
	accepted := librarySuccess(t, Invoke(ctx, Bind(listener, "", "accept"), nil))
	connection := librarySuccess(t, <-connected)
	defer Invoke(Shield(ctx), Bind(connection, "", "close"), nil)
	defer Invoke(Shield(ctx), Bind(accepted, "", "close"), nil)
	Invoke(ctx, Bind(connection, "", "write"), []Argument{{"data", Bytes{[]byte("x")}}})
	read := librarySuccess(t, Invoke(ctx, Bind(accepted, "", "read"), nil)).(Alternative)
	if read.Tag != "some" || string(read.Fields[0].(Bytes).Items) != "x" {
		t.Fatal("default read/deadline")
	}
	libraryFailure(t, Invoke(ctx, Bind(listener, "", "accept"), []Argument{{"timeout", optional("@std/Duration", Duration(0), true)}}), "Timeout")
}

func TestWebsocketOmittedDeadline(t *testing.T) {
	upgraded := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(5 * time.Millisecond)
		conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		close(upgraded)
		conn.ReadMessage()
	}))
	defer server.Close()
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(Shield(ctx), nil)
	options := Record{"@std/WebSocketOptions", map[string]Value{"tls": networkingTLSOptions(), "compression": false}}
	value := librarySuccess(t, Invoke(ctx, n.Operation("web_socket"), []Argument{{"url", "ws" + strings.TrimPrefix(server.URL, "http")}, {"headers", &Map{Type: "@std/Map[String][String]"}}, {"subprotocols", libraryStrings(nil)}, {"options", options}}))
	<-upgraded
	Invoke(ctx, Bind(value, "", "close"), nil)
}

func TestHTTPOmittedBudgets(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(Shield(ctx), nil)
	handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, _ []Value) Value {
		return Record{"@std/HttpResponse", map[string]Value{"status": int32(200), "headers": &Map{Type: "@std/Map[String][String]"}, "body": Bytes{[]byte("ok")}}}
	})
	server := librarySuccess(t, Invoke(ctx, n.Operation("serve"), []Argument{{"address", "127.0.0.1:0"}, {"handler", handler}}))
	defer Invoke(ctx, Bind(server, "", "close"), nil)
	address := Invoke(ctx, Bind(server, "", "address"), nil).(string)
	response := librarySuccess(t, Invoke(ctx, n.Operation("request"), []Argument{{"method", "GET"}, {"url", "http://" + address}, {"headers", &Map{Type: "@std/Map[String][String]"}}, {"body", Bytes{}}})).(Record)
	if response.Fields["status"] != int32(200) || string(response.Fields["body"].(Bytes).Items) != "ok" {
		t.Fatal(response)
	}
}
