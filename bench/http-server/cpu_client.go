// A low-overhead persistent-connection client for checking whole-handler CPU scaling.
package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

func main() {
	address := flag.String("address", "http://127.0.0.1:19747/cpu", "CPU route")
	seconds := flag.Duration("duration", 5*time.Second, "measurement interval")
	clients := flag.Int("clients", 64, "concurrent persistent connections")
	flag.Parse()
	transport := &http.Transport{MaxIdleConns: *clients, MaxIdleConnsPerHost: *clients, MaxConnsPerHost: *clients}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
	var lock sync.Mutex
	var group sync.WaitGroup
	statuses, members, failures := map[int]int{}, map[string]int{}, map[string]int{}
	latencies := []float64{}
	started := time.Now()
	end := started.Add(*seconds)
	for i := 0; i < *clients; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			for time.Now().Before(end) {
				begin := time.Now()
				response, err := client.Get(*address)
				var body []byte
				if err == nil {
					body, err = io.ReadAll(response.Body)
					response.Body.Close()
				}
				lock.Lock()
				latencies = append(latencies, float64(time.Since(begin).Microseconds())/1000)
				if err != nil {
					failures[err.Error()]++
				} else {
					statuses[response.StatusCode]++
					if response.StatusCode == 200 {
						identity := response.Header.Get("X-Benchmark-Upstream")
						if identity == "" {
							identity = strings.SplitN(string(body), ":", 2)[0]
						}
						members[identity]++
					}
				}
				lock.Unlock()
			}
		}()
	}
	group.Wait()
	elapsed := time.Since(started).Seconds()
	sort.Float64s(latencies)
	percentile := func(q float64) float64 {
		if len(latencies) == 0 {
			return 0
		}
		return latencies[int(float64(len(latencies)-1)*q)]
	}
	count := 0
	for _, n := range statuses {
		count += n
	}
	json.NewEncoder(os.Stdout).Encode(map[string]any{"throughput": float64(count) / elapsed, "load_seconds": elapsed, "statuses": statuses, "errors": failures, "members": members, "p50_ms": percentile(.5), "p99_ms": percentile(.99)})
}
