//go:build linux

// Linux-only benchmark deployment: independent local servers behind a Go proxy.
package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"
)

type member struct {
	cmd  *exec.Cmd
	done chan error
}

func run() error {
	if len(os.Args) != 4 {
		return fmt.Errorf("usage: proxy-group SERVER MEMBERS ADDRESS")
	}
	count, err := strconv.Atoi(os.Args[2])
	if err != nil || count < 1 || count > 64 {
		return fmt.Errorf("invalid member count")
	}
	host, portText, err := net.SplitHostPort(os.Args[3])
	if err != nil {
		return err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port+count > 65535 {
		return fmt.Errorf("invalid port range")
	}
	var members []member
	defer func() {
		for _, m := range members {
			_ = m.cmd.Process.Signal(syscall.SIGTERM)
		}
		deadline := time.Now().Add(3 * time.Second)
		for _, m := range members {
			select {
			case <-m.done:
			case <-time.After(time.Until(deadline)):
				_ = m.cmd.Process.Kill()
				<-m.done
			}
		}
	}()
	transport := &http.Transport{MaxIdleConns: 1024, MaxIdleConnsPerHost: 256, MaxConnsPerHost: 256}
	defer transport.CloseIdleConnections()
	proxies := make([]*httputil.ReverseProxy, count)
	probe := &http.Client{Timeout: time.Second}
	defer probe.CloseIdleConnections()
	for i := 0; i < count; i++ {
		address := net.JoinHostPort(host, strconv.Itoa(port+i+1))
		cmd := exec.Command(os.Args[1], "local", "1", address)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		// A forcibly stopped harness must not leave independent servers behind.
		cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
		if err := cmd.Start(); err != nil {
			return err
		}
		done := make(chan error, 1)
		members = append(members, member{cmd, done})
		go func() { done <- cmd.Wait(); close(done) }()
		target, _ := url.Parse("http://" + address)
		ready := false
		for attempt := 0; attempt < 200; attempt++ {
			response, err := probe.Get(target.String() + "/")
			if err == nil {
				response.Body.Close()
				ready = response.StatusCode == http.StatusOK
			}
			if ready {
				break
			}
			select {
			case err := <-done:
				return fmt.Errorf("backend exited during startup: %v", err)
			default:
			}
			time.Sleep(10 * time.Millisecond)
		}
		if !ready {
			return fmt.Errorf("backend readiness timed out")
		}
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.Transport = transport
		identity := strconv.Itoa(i)
		proxy.ModifyResponse = func(response *http.Response) error {
			response.Header.Set("X-Benchmark-Upstream", identity)
			return nil
		}
		proxies[i] = proxy
	}
	var next atomic.Uint64
	server := &http.Server{Addr: os.Args[3], Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		proxies[(next.Add(1)-1)%uint64(count)].ServeHTTP(w, r)
	})}
	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(stopped)
	errors := make(chan error, 1)
	go func() { errors <- server.ListenAndServe() }()
	select {
	case <-stopped:
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		return server.Shutdown(ctx)
	case err := <-errors:
		return err
	}
}

func main() {
	runtime.LockOSThread()
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
