package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	var (
		helpFlag bool
		// verboseFlag bool
		// debugFlag   bool
		versionFlag bool
		// noColorFlag bool
	)
	flag.BoolVar(&helpFlag, "h", false, "Show help")
	flag.BoolVar(&helpFlag, "help", false, "Show help")
	// flag.BoolVar(&verboseFlag, "v", false, "Enable verbose mode")
	// flag.BoolVar(&verboseFlag, "verbose", false, "Enable verbose mode")
	// flag.BoolVar(&debugFlag, "d", false, "Enable debug mode")
	// flag.BoolVar(&debugFlag, "debug", false, "Enable debug mode")
	flag.BoolVar(&versionFlag, "V", false, "Show version")
	flag.BoolVar(&versionFlag, "version", false, "Show version")
	// flag.BoolVar(&noColorFlag, "no-color", false, "Disable colors")

	flag.Parse()

	switch {
	case helpFlag:
		help()
		os.Exit(0)
	case versionFlag:
		version()
		os.Exit(0)
	default:
		fmt.Println("wrong Flag")
		os.Exit(1)
	}

	args := flag.Args()

	switch args[0] {
	case "add":
		add()
		os.Exit(0)
	case "collect":
		collect()
		os.Exit(0)
	case "check":
		check()
		os.Exit(0)
	default:
		fmt.Println("wrong Argument")
		os.Exit(1)
	}
}

func help() {
	text, err := os.ReadFile("scripts/helpMigration.txt")
	if err != nil {
		fmt.Println("Error reading help file:", err)
		os.Exit(1)
	}
	fmt.Println(string(text))
}

func version() {
	Version := "0.1"
	fmt.Println(Version)
}

func verbose() {
	fmt.Println("verbose")
}

func debug() {
	fmt.Println("debug")
}

func noColor() {
	fmt.Println("no-color")
}

func add() {
	fmt.Println("add")
}

func collect() {
	fmt.Println("collect")
}

func check() {
	fmt.Println("check")
}
