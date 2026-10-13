package msruntime

import (
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestSynchronizedHTTPShutdownJoinsShieldedCleanup(t *testing.T) {
	for _, streaming := range []bool{false, true} {
		name := "buffered"
		if streaming {
			name = "streaming"
		}
		t.Run(name, func(t *testing.T) {
			root := RootExecution()
			cell := synchronizedInt()
			guard := lockCell(root, cell)
			entered := make(chan struct{})
			faults := make(chan any, 1)
			body := func(child *Execution, _ []Value) Value {
				defer func() {
					failure := recovered(func() { locked := lockCell(Shield(child), cell); locked.close() })
					faults <- failure
					if failure != nil {
						panic(failure)
					}
				}()
				close(entered)
				<-child.Context.Done()
				CheckCancelled(child)
				return hostResponse(200, "")
			}
			var service *httpService
			if streaming {
				network := &network{}
				handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", body)
				options := networkingServerOptions()
				options.Fields["grace"] = Duration(0)
				value := librarySuccess(t, network.Operation("serve_stream").Body(root, []Value{"127.0.0.1:0", handler, options}))
				service = value.(View).Receiver.(*httpService)
			} else {
				service = serveTest(t, root, NewFunction([]string{"request"}, "@std/HttpResponse", body), 32)
			}
			t.Cleanup(func() { guard.close(); service.close(root) })
			finished := make(chan struct{})
			client := &http.Client{Timeout: 2 * time.Second}
			go func() {
				defer close(finished)
				response, err := client.Get("http://" + service.listener.Addr().String())
				if err == nil {
					io.Copy(io.Discard, response.Body)
					response.Body.Close()
				}
			}()
			awaitSynchronizedSignal(t, entered)
			outcome := awaitSynchronizedCall(t, synchronizedCall(func() Value { service.close(root); return Unit{} }))
			if outcome.failure != nil {
				t.Fatal(outcome.failure)
			}
			select {
			case failure := <-faults:
				if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "ancestor waiting") {
					t.Fatal("HTTP shutdown skipped an ancestral cleanup cycle", failure)
				}
			default:
				t.Fatal("HTTP close returned before request cleanup")
			}
			awaitSynchronizedSignal(t, finished)
			guard.close()
			requireWorkWaitsClear(t, root, &service.waits)
		})
	}
}
