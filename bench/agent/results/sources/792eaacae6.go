package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

type record struct {
	timestamp string
	level     string
	method    string
	path      string
	status    string
	latency   int64
	latStr    string
}

func isDigits(s string) bool {
	if len(s) == 0 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// parseLine returns a record and true if the line is valid.
func parseLine(line string) (record, bool) {
	fields := strings.Split(line, " ")
	if len(fields) != 6 {
		return record{}, false
	}
	ts, level, method, path, status, lat := fields[0], fields[1], fields[2], fields[3], fields[4], fields[5]
	if ts == "" {
		return record{}, false
	}
	switch level {
	case "DEBUG", "INFO", "WARN", "ERROR":
	default:
		return record{}, false
	}
	switch method {
	case "GET", "POST", "PUT", "DELETE":
	default:
		return record{}, false
	}
	if path == "" || path[0] != '/' {
		return record{}, false
	}
	if len(status) != 3 || !isDigits(status) {
		return record{}, false
	}
	if len(lat) < 1 || len(lat) > 9 || !isDigits(lat) {
		return record{}, false
	}
	v, err := strconv.ParseInt(lat, 10, 64)
	if err != nil {
		return record{}, false
	}
	return record{
		timestamp: ts,
		level:     level,
		method:    method,
		path:      path,
		status:    status,
		latency:   v,
		latStr:    lat,
	}, true
}

type pathStat struct {
	path  string
	count int64
	total int64
}

func main() {
	reader := bufio.NewReaderSize(os.Stdin, 1<<20)
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()

	var recs []record
	malformed := 0

	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 || err == nil {
			line = strings.TrimSuffix(line, "\n")
			if strings.TrimSpace(line) == "" {
				// skipped entirely
			} else if r, ok := parseLine(line); ok {
				recs = append(recs, r)
			} else {
				malformed++
			}
		}
		if err != nil {
			if err != io.EOF {
				fmt.Fprintln(os.Stderr, err)
			}
			break
		}
	}

	counts := map[string]int{}
	var c2, c3, c4, c5, cOther int
	paths := map[string]*pathStat{}
	for _, r := range recs {
		counts[r.level]++
		switch r.status[0] {
		case '2':
			c2++
		case '3':
			c3++
		case '4':
			c4++
		case '5':
			c5++
		default:
			cOther++
		}
		ps := paths[r.path]
		if ps == nil {
			ps = &pathStat{path: r.path}
			paths[r.path] = ps
		}
		ps.count++
		ps.total += r.latency
	}

	fmt.Fprintf(w, "valid: %d\n", len(recs))
	fmt.Fprintf(w, "malformed: %d\n", malformed)
	fmt.Fprintf(w, "DEBUG: %d\n", counts["DEBUG"])
	fmt.Fprintf(w, "INFO: %d\n", counts["INFO"])
	fmt.Fprintf(w, "WARN: %d\n", counts["WARN"])
	fmt.Fprintf(w, "ERROR: %d\n", counts["ERROR"])
	fmt.Fprintf(w, "status: 2xx=%d 3xx=%d 4xx=%d 5xx=%d other=%d\n", c2, c3, c4, c5, cOther)

	n := len(recs)
	if n == 0 {
		fmt.Fprintf(w, "p95: 0\n")
	} else {
		lats := make([]int64, n)
		for i, r := range recs {
			lats[i] = r.latency
		}
		sort.Slice(lats, func(i, j int) bool { return lats[i] < lats[j] })
		rank := (95*n + 99) / 100
		fmt.Fprintf(w, "p95: %d\n", lats[rank-1])

		best := 0
		for i, r := range recs {
			if r.latency > recs[best].latency {
				best = i
			}
		}
		b := recs[best]
		fmt.Fprintf(w, "slowest: %s %s %s %s\n", b.latStr, b.method, b.path, b.timestamp)
	}

	fmt.Fprintf(w, "top:\n")
	list := make([]*pathStat, 0, len(paths))
	for _, ps := range paths {
		list = append(list, ps)
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].count != list[j].count {
			return list[i].count > list[j].count
		}
		return list[i].path < list[j].path
	})
	if len(list) > 3 {
		list = list[:3]
	}
	for _, ps := range list {
		fmt.Fprintf(w, "%s %d avg=%d\n", ps.path, ps.count, ps.total/ps.count)
	}
}
