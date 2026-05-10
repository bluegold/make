package main

import (
	"fmt"
	"os"

	"make/taskrunner"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: program <taskfile> [target]")
		os.Exit(1)
	}

	taskfile := os.Args[1]
	target := ""
	if len(os.Args) > 2 {
		target = os.Args[2]
	}

	if err := taskrunner.RunLevel2(taskfile, target); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
