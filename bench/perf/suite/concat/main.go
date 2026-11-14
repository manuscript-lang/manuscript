package main

import (
	"fmt"
	"strconv"
	"strings"
)

func main() {
	a := ""
	for i := 0; i < 50000; i++ {
		a += strconv.Itoa(i)
	}
	b := ""
	for i := 0; i < 50000; i++ {
		b += fmt.Sprintf("item-%d,", i)
	}
	c := ""
	for i := 0; i < 50000; i++ {
		c += "item,"
	}
	parts := make([]string, 0, 100000)
	for i := 0; i < 50000; i++ {
		parts = append(parts, fmt.Sprintf("p%d", i))
	}
	d := strings.Join(parts, ",")
	fmt.Println(len(a), len(b), len(c), len(d))
}
