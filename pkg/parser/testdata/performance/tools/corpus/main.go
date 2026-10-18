package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func main() {
	manifest, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	for _, file := range strings.Fields(string(manifest)) {
		source, err := os.ReadFile(file)
		if err != nil {
			panic(err)
		}
		for _, ending := range []string{"original", "CRLF", "mixed"} {
			text := strings.ReplaceAll(string(source), "\r\n", "\n")
			switch ending {
			case "original":
				text = string(source)
			case "CRLF":
				text = strings.ReplaceAll(text, "\n", "\r\n")
			case "mixed":
				lines := strings.SplitAfter(text, "\n")
				for i := range lines {
					if i%2 == 0 {
						lines[i] = strings.ReplaceAll(lines[i], "\n", "\r\n")
					}
				}
				text = strings.Join(lines, "")
			}
			tokens, lexErr := lexer.Lex(file, text)
			module, parseErr := parser.Parse(file, text)
			partial, issues := parser.ParsePartial(file, text)
			data, err := json.Marshal([]any{tokens, lexErr, module, parseErr, partial, issues})
			if err != nil {
				panic(err)
			}
			fmt.Printf("%s %s %x\n", file, ending, sha256.Sum256(data))
		}
	}
}
