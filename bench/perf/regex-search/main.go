// Go port of main.ms: find_all, spans, replace_all and a second pattern over one text file.
package main

import (
	"fmt"
	"os"
	"regexp"
)

func main() {
	raw, _ := os.ReadFile("/tmp/regex-search-input.txt")
	data := string(raw)
	re := regexp.MustCompile(`func\s+\w+\(`)
	all := re.FindAllString(data, -1)
	spans := re.FindAllStringIndex(data, -1)
	rep := re.ReplaceAllString(data, "fn(")
	w := regexp.MustCompile(`[A-Za-z_]+[0-9]+`).FindAllString(data, -1)
	fmt.Println(len(all), len(spans), len(rep), len(w))
}
