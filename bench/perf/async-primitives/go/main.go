// Go port of main.ms: the same modes with goroutines and channels.
package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"time"
)

func work(a int) int { return a*2 + 1 }

func runSpawn(n int) int {
	total := 0
	for i := 0; i < n; i++ {
		ch := make(chan int, 1)
		go func(i int) { ch <- work(i) }(i)
		total += <-ch
	}
	return total
}

func runBatch(n int) int {
	total := 0
	for done := 0; done < n; done += 64 {
		chans := make([]chan int, 0, 64)
		for i := 0; i < 64; i++ {
			ch := make(chan int, 1)
			go func(v int) { ch <- work(v) }(done + i)
			chans = append(chans, ch)
		}
		for _, ch := range chans {
			total += <-ch
		}
	}
	return total
}

func runPingpong(n int) int {
	requests := make(chan int, 1)
	replies := make(chan int, 1)
	go func() {
		for v := range requests {
			replies <- v + 1
		}
		close(replies)
	}()
	total := 0
	for i := 0; i < n; i++ {
		requests <- i
		total += <-replies
	}
	close(requests)
	return total
}

func runStream(n int) int {
	values := make(chan int, 64)
	go func() {
		for i := 0; i < n; i++ {
			values <- i
		}
		close(values)
	}()
	total := 0
	for v := range values {
		total += v
	}
	return total
}

func runSleep(n int) int {
	for i := 0; i < n; i++ {
		<-time.NewTimer(0).C
	}
	return n
}

func runEcho(n int) int {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			panic(err)
		}
		buf := make([]byte, 65536)
		for {
			got, err := conn.Read(buf)
			if err != nil {
				conn.Close()
				return
			}
			if _, err := conn.Write(buf[:got]); err != nil {
				panic(err)
			}
		}
	}()
	client, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		panic(err)
	}
	message := []byte("0123456789012345678901234567890123456789012345678901234567890123")
	buf := make([]byte, 65536)
	total := 0
	for i := 0; i < n; i++ {
		if _, err := client.Write(message); err != nil {
			panic(err)
		}
		got, err := io.ReadAtLeast(client, buf, 1)
		if err != nil {
			panic(err)
		}
		total += got
	}
	client.Close()
	return total
}

func main() {
	mode := os.Args[1]
	n, _ := strconv.Atoi(os.Args[2])
	before := time.Now()
	total := 0
	switch mode {
	case "inline", "here":
		total = runSpawn(n)
	case "batch", "batch-here":
		total = runBatch(n)
	case "pingpong":
		total = runPingpong(n)
	case "stream":
		total = runStream(n)
	case "sleep":
		total = runSleep(n)
	case "echo":
		total = runEcho(n)
	}
	fmt.Printf("%s total %d ns/op %d\n", mode, total, time.Since(before).Nanoseconds()/int64(n))
}
