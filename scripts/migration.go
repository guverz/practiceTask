package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
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
		// os.Exit(1)
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

func describe(arg string) (string, error) {
	cmd := exec.Command("scripts/describe.sh", arg)
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to run describe %s: %v", arg, err)
	}
	return string(output), nil
	// should check whether describe works
}

func add() {
	project, err := describe("project")
	if err != nil {
		log.Fatal(err)
	}
	version, err := describe("version")
	if err != nil {
		log.Fatal(err)
	}
	release, err := describe("release")
	if err != nil {
		log.Fatal(err)
	}
	baseName := fmt.Sprintf("%s-%s-%s", project, version, release)
	fmt.Println(project, version, release)
	fmt.Printf("Add migration script %s\n", baseName)

}

func collect() {
	fmt.Println("collect")
}

func check() {
	fmt.Println("check")
}
