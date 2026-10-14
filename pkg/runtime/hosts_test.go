package msruntime

import (
	"context"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

func hostResponse(status int64, text string) Value {
	return Record{"@std/HttpResponse", map[string]Value{"status": status, "headers": httpTestHeaders(&Map{Type: "@std/Map[String][String]"}), "body": Bytes{[]byte(text)}}}
}
func serveTest(t *testing.T, root *Execution, handler Function, bodyLimit int64) *httpService {
	t.Helper()
	network := &network{}
	result := Invoke(root, network.Operation("serve"), []Argument{{"address", "127.0.0.1:0"}, {"handler", handler}, {"max_requests", int64(1)}, {"max_body_bytes", bodyLimit}, {"max_response_bytes", int64(32)}, {"timeout", Duration(time.Second)}, {"grace", Duration(0)}}).(Alternative)
	if result.Tag != "ok" {
		t.Fatal(result)
	}
	service := result.Fields[0].(View).Receiver.(*httpService)
	t.Cleanup(func() { service.close(root) })
	return service
}
func TestHTTPBodyLimitsAndResponse(t *testing.T) {
	root := RootExecution()
	handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, args []Value) Value {
		request := args[0].(Record)
		return hostResponse(201, string(request.Fields["body"].(Bytes).Items))
	})
	service := serveTest(t, root, handler, 4)
	client := &http.Client{Timeout: 2 * time.Second}
	for body, status := range map[string]int{"data": 201, "oversized": 413} {
		response, err := client.Post("http://"+service.listener.Addr().String()+"/hello", "application/octet-stream", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		output, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil || response.StatusCode != status {
			t.Fatalf("body=%s response=%d %s error=%v", body, response.StatusCode, output, err)
		}
		if status == 201 && string(output) != "data" {
			t.Fatal(string(output))
		}
	}
	service.close(root)
	if len(service.owner.servers) != 0 || len(root.Lifetime.services) != 0 {
		t.Fatal("closed HTTP service retained")
	}
}
func TestHTTPBoundedAdmissionAndJoinedShutdown(t *testing.T) {
	root := RootExecution()
	entered := make(chan struct{})
	exited := make(chan struct{})
	handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(ctx *Execution, _ []Value) Value {
		close(entered)
		defer close(exited)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return hostResponse(200, "")
	})
	service := serveTest(t, root, handler, 8)
	client := &http.Client{Timeout: 2 * time.Second}
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		response, err := client.Get("http://" + service.listener.Addr().String())
		if err == nil {
			io.Copy(io.Discard, response.Body)
			response.Body.Close()
		}
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("request not admitted")
	}
	response, err := client.Get("http://" + service.listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 503 {
		t.Fatal(response.StatusCode)
	}
	service.close(root)
	select {
	case <-exited:
	default:
		t.Fatal("shutdown did not join request")
	}
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("client request retained")
	}
}
func TestHTTPOwnRequestCannotCloseHost(t *testing.T) {
	root := RootExecution()
	service := serveTest(t, root, NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, _ []Value) Value { return hostResponse(200, "") }), 8)
	request := inherit(root, root.Context)
	request.HostServices = map[*httpService]bool{service: true}
	if _, ok := recovered(func() { service.close(request) }).(Fault); !ok {
		t.Fatal("own request close did not fail")
	}
	if service.closing {
		t.Fatal("failed self close changed admission")
	}
}
func TestStreamCancellationAndConcurrentClose(t *testing.T) {
	for _, mode := range []string{"cancel", "close"} {
		t.Run(mode, func(t *testing.T) {
			read, write, err := os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			defer read.Close()
			defer write.Close()
			stream := &stream{file: read, owned: mode == "close", resultType: "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			execution := inherit(RootExecution(), ctx)
			finished := make(chan any, 1)
			go func() {
				finished <- recovered(func() {
					value := Invoke(execution, stream.Operation("read"), []Argument{{"max_bytes", int64(8)}}).(Alternative)
					if value.Tag != "error" {
						panic("closed read succeeded")
					}
				})
			}()
			// Wait for admission without relying on a scheduler delay.
			deadline := time.Now().Add(time.Second)
			for {
				stream.mu.Lock()
				active := stream.admitted
				stream.mu.Unlock()
				if active > 0 {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("read not admitted")
				}
				time.Sleep(time.Millisecond)
			}
			if mode == "cancel" {
				cancel()
			} else {
				Invoke(RootExecution(), stream.Operation("close"), nil)
			}
			select {
			case fault := <-finished:
				if mode == "cancel" {
					if _, ok := fault.(cancelled); !ok {
						t.Fatal(fault)
					}
				} else if fault != nil {
					t.Fatal(fault)
				}
			case <-time.After(time.Second):
				t.Fatal("blocked stream operation retained")
			}
		})
	}
}
func TestSubprocessOutputAndLimit(t *testing.T) {
	if _, err := os.Stat("/bin/printf"); err != nil {
		t.Skip("requires POSIX printf")
	}
	root := RootExecution()
	commands := &commands{}
	for limit, tag := range map[int64]string{8: "ok", 2: "error"} {
		result := Invoke(root, commands.Operation("run"), []Argument{{"program", "/bin/printf"}, {"arguments", &List{Items: []Value{"hello"}}}, {"input", Bytes{}}, {"max_output_bytes", limit}, {"timeout", Duration(time.Second)}}).(Alternative)
		if result.Tag != tag {
			t.Fatal(result)
		}
		if tag == "ok" {
			output := result.Fields[0].(Record)
			if string(output.Fields["stdout"].(Bytes).Items) != "hello" || output.Fields["exit_code"] != int64(0) {
				t.Fatal(output)
			}
		} else if result.Fields[0].(Alternative).Tag != "OutputLimit" {
			t.Fatal(result)
		}
	}
	result := Invoke(root, commands.Operation("run"), []Argument{{"program", "/bin/printf"}, {"arguments", &List{}}, {"input", Bytes{}}, {"max_output_bytes", int64(8)}, {"timeout", Duration(0)}}).(Alternative)
	if result.Tag != "error" || result.Fields[0].(Alternative).Tag != "TimedOut" {
		t.Fatal(result)
	}
}
