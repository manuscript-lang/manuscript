package compile

import (
	"fmt"
	"manuscript-lang/manuscript/internal/config"
)

func RunFile(filename string) {
	ctx, err := config.NewCompilerContextFromFile(filename, "", "")
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}

	result := CompileManuscript(ctx)
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
		return
	}
	fmt.Print(result.GoCode)

}
