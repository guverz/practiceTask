package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	MiniHelp = `################################################################################
## !!! Don't forget connect to database source, uncomment:
#connect source
## Source may be a source name from configuration file
## Or it a connect string in format:
#connect Driver://user:password@host[:port]/dbname
################################################################################
## Requests must be separated by ';' delimeter
#select sysdate from dual;
################################################################################
## Use '/' for delimeter PL/SQL code, begin end or create functions, procedures,
## Packages and any other object that contain PL/SQL code, exmaple
#begin
#   -- any pl/sql code
#end;
#/
################################################################################
## Script could include another file with sql:
#@include.sql
## !!! Avoid include migration scripts
################################################################################
## To continue or break on specific errors use:
#whenever error [pattern] continue|break
################################################################################
## Additional help
## roam-sql -h|--help for command line options
## roam-sql -i|--info for syntax help`
	MigrationDir = "./migrations"
	IncludeHelp  = true
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
		// default:
		// 	fmt.Println("wrong Flag")
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
	return strings.ReplaceAll(string(output), "\n", ""), nil
	// should check whether describe works
}

func add() error {
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
	fmt.Printf("Add migration script %s\n", baseName)

	increment, err := FindLastMigrationNumber(MigrationDir, baseName)
	if err != nil {
		return fmt.Errorf("failed to find last migration: %v", err)
	}
	increment++

	migrationFile := fmt.Sprintf("%s-%d", baseName, increment)
	err = CreateMigrationFiles(MigrationDir, migrationFile, IncludeHelp)
	if err != nil {
		return fmt.Errorf("failed to create migration files: %v", err)
	}

	fmt.Printf("Created migration files:\n   %s/%s.up.sql\n   %s/%s.down.sql\n",
		MigrationDir, migrationFile, MigrationDir, migrationFile)

	return nil
}

func FindLastMigrationNumber(dir, baseName string) (int, error) {
	pattern := regexp.MustCompile(fmt.Sprintf(`^%s-(\d+)\.(up|down)\.sql$`, regexp.QuoteMeta(baseName)))
	var maxNum int

	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, fmt.Errorf("failed to read directory %s: %v", dir, err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		matches := pattern.FindStringSubmatch(entry.Name())
		if len(matches) > 1 {
			num, err := strconv.Atoi(matches[1])
			if err != nil {
				continue
			}
			if num > maxNum {
				maxNum = num
			}
		}
	}

	return maxNum, nil
}

func CreateMigrationFiles(dir, baseName string, includeHelp bool) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	upContent := fmt.Sprintf("# %s.up.sql\n", baseName)
	if includeHelp {
		upContent += MiniHelp + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, baseName+".up.sql"), []byte(upContent), 0644); err != nil {
		return err
	}

	downContent := fmt.Sprintf("# %s.down.sql\n", baseName)
	if includeHelp {
		downContent += MiniHelp + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, baseName+".down.sql"), []byte(downContent), 0644); err != nil {
		return err
	}

	return nil
}

func collect() {
	fmt.Println("collect")
}

func check() {
	fmt.Println("check")
}
