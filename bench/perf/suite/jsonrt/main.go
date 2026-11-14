package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func makeText(n int) string {
	var sb strings.Builder
	x := 1
	sb.WriteString("[")
	for i := 0; i < n; i++ {
		x = lcg(x)
		if i > 0 {
			sb.WriteString(",")
		}
		fmt.Fprintf(&sb, `{"id":%d,"name":"item-%d","score":%d,"tags":["t%d","t%d"],"nested":{"a":%d,"b":[%d,%d]}}`,
			i, x%1000, x/7%10000, x%7, x%11, x%5, x%3, x%13)
	}
	sb.WriteString("]")
	return sb.String()
}

func walk(v interface{}) int {
	switch t := v.(type) {
	case nil:
		return 1
	case bool:
		return 1
	case float64:
		return int(t)
	case string:
		return len([]rune(t))
	case []interface{}:
		total := 0
		for _, item := range t {
			total += walk(item)
		}
		return total
	case map[string]interface{}:
		total := 0
		for k, item := range t {
			total += len(k) + walk(item)
		}
		return total
	}
	return 0
}

func main() {
	text := makeText(120000)
	total, outLen := 0, 0
	for pass := 0; pass < 3; pass++ {
		var doc interface{}
		if err := json.Unmarshal([]byte(text), &doc); err != nil {
			panic(err)
		}
		total += walk(doc)
		out, _ := json.Marshal(doc)
		outLen += len(out)
	}
	fmt.Printf("text %d walk %d out %d\n", len(text), total, outLen)
}
