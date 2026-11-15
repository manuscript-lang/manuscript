// Query throughput: WORKERS connections each run QUERIES sequential point lookups with one
// prepared statement. Matches ms/src/main.ms.
package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"sync"

	"github.com/jackc/pgx/v5"
)

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func worker(url string, id, queries int) (int64, error) {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, url)
	if err != nil {
		return 0, err
	}
	defer conn.Close(ctx)
	if _, err := conn.Prepare(ctx, "lookup", "select id, name, score from items where id = $1"); err != nil {
		return 0, err
	}
	var sum int64
	for i := 0; i < queries; i++ {
		key := int64((i*7919+id*104729)%10000 + 1)
		var rowID, score int64
		var name string
		if err := conn.QueryRow(ctx, "lookup", key).Scan(&rowID, &name, &score); err != nil {
			return 0, err
		}
		sum += score
	}
	return sum, nil
}

func main() {
	workers, _ := strconv.Atoi(env("WORKERS", "4"))
	queries, _ := strconv.Atoi(env("QUERIES", "20000"))
	url := fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable",
		env("PGUSER", "postgres"), env("PGPASSWORD", ""), env("PGHOST", "127.0.0.1"), env("PGPORT", "5432"))
	sums := make([]int64, workers)
	errs := make([]error, workers)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			sums[w], errs[w] = worker(url, w, queries)
		}(w)
	}
	wg.Wait()
	var total int64
	for w := 0; w < workers; w++ {
		if errs[w] != nil {
			fmt.Fprintln(os.Stderr, errs[w])
			os.Exit(1)
		}
		total += sums[w]
	}
	fmt.Printf("checksum %d\n", total)
}
