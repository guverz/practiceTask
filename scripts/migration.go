package main

import (
	"crypto/md5"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	// "time"
)

const (
	Help = `migration helper to create migrations scripts
usage: migration [-h|--help] [-V|--version] add
options:
        -h|--help      print this help and exit
        -V|--version   print script version and exit
commands:
        add            add new migrations script with properly defined name
        collect        collect migrations on submodules between commits into migrations catalog
        check          check unregtistered migrations files at submodules`
	MiniHelpDir      = "scripts/migration.template.sql"
	MigrationDir     = "./migrations"
	IncludeHelp      = true
	MainDescribePath = "scripts/describe.sh"
	GitBashPath      = "C:\\Program Files\\Git\\bin\\bash.exe"
	Shell            = "bin/bash"
)

type metaInfo struct {
	Project  string
	Version  string
	Release  string
	MD5      string
	Path     string
	Type     string // "up" || "down"
	BaseName string // no .up.sql || .down.sql
}

func main() {

	var (
		helpFlag    bool
		versionFlag bool
	)

	flag.Usage = func() {}

	flag.BoolVar(&helpFlag, "h", false, "print help and exit")
	flag.BoolVar(&helpFlag, "help", false, "print help and exit")
	flag.BoolVar(&versionFlag, "V", false, "print script version and exit")
	flag.BoolVar(&versionFlag, "version", false, "print script version and exit")

	err := flag.CommandLine.Parse(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Unknown flag provided\n")
		os.Exit(1)
	}

	switch {
	case helpFlag:
		help()
		os.Exit(0)
	case versionFlag:
		version()
		os.Exit(0)
	}

	if flag.NArg() == 0 && flag.NFlag() > 0 {
		fmt.Fprintf(os.Stderr, "Error: Unknown flag provided\n")
		os.Exit(0)
	}

	args := flag.Args()
	if len(args) == 0 {
		os.Exit(0)
	}

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
		fmt.Fprintf(os.Stderr, "Error: Unknown command '%s'\n", args[0])
		os.Exit(0)
	}
}

func help() {
	fmt.Println(Help)
}

func minihelp() string {
	text, err := os.ReadFile(MiniHelpDir)
	if err != nil {
		fmt.Println("Error reading help file:", err)
	}
	return string(text)
}

func version() {
	Version := "0.1"
	fmt.Println(Version)
}

func describe(scriptPath, arg string) (string, error) {
	// should think of implementing wsl use for windows
	var cmd *exec.Cmd
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return "", fmt.Errorf("script not found at %s", scriptPath)
	}
	if runtime.GOOS == "windows" {
		if _, err := os.Stat(GitBashPath); err == nil {
			cmd = exec.Command(GitBashPath, "-c", fmt.Sprintf("./%s %s", scriptPath, arg))
		} else {
			return "", fmt.Errorf("bash not found on Windows")
		}
	} else {
		cmd = exec.Command(Shell, scriptPath, arg)
	}

	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to run describe %s: %v", arg, err)
	}
	return strings.ReplaceAll(string(output), "\n", ""), nil
}

func add() error {
	project, err := describe(MainDescribePath, "project")
	if err != nil {
		log.Fatal(err)
	}
	version, err := describe(MainDescribePath, "version")
	if err != nil {
		log.Fatal(err)
	}
	release, err := describe(MainDescribePath, "release")
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
		upContent += minihelp() + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, baseName+".up.sql"), []byte(upContent), 0644); err != nil {
		return err
	}

	downContent := fmt.Sprintf("# %s.down.sql\n", baseName)
	if includeHelp {
		downContent += minihelp() + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, baseName+".down.sql"), []byte(downContent), 0644); err != nil {
		return err
	}

	return nil
}

// fill-in metaInfo
func getMigrationMetaMap(dir string, describePath string) (map[string]metaInfo, error) {
	m := make(map[string]metaInfo)
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return m, nil
		}
		return nil, err
	}
	project, _ := describe(describePath, "project")
	version, _ := describe(describePath, "version")
	release, _ := describe(describePath, "release")
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".up.sql") || strings.HasSuffix(name, ".down.sql") {
			path := filepath.Join(dir, name)
			_, md5 := parseMigrationMeta(path)
			typeStr := "up"
			if strings.HasSuffix(name, ".down.sql") {
				typeStr = "down"
			}
			base := strings.TrimSuffix(strings.TrimSuffix(name, ".up.sql"), ".down.sql")
			m[base+"|"+typeStr] = metaInfo{
				Project:  project,
				Version:  version,
				Release:  release,
				MD5:      md5,
				Path:     path,
				Type:     typeStr,
				BaseName: base,
			}
		}
	}
	return m, nil
}

func collect() {
	mainMap, _ := getMigrationMetaMap(MigrationDir, MainDescribePath)

	submodules, err := getSubmodules()
	if err != nil {
		fmt.Println("Error getting submodules:", err)
		os.Exit(1)
	}

	totalAdded, totalUpdated, totalDeleted := 0, 0, 0
	// gathering all migration-files from submodules
	subMap := make(map[string]metaInfo)
	for _, sub := range submodules {
		describeScript, _ := findDescribeScript(sub)
		subMigDir := filepath.Join(sub, "migrations")
		m, _ := getMigrationMetaMap(subMigDir, describeScript)
		for k, v := range m {
			subMap[sub+"|"+k] = v
		}
	}

	//  add new and update changed
	for _, v := range subMap {
		// creating name
		baseName := fmt.Sprintf("%s-%s-%s-%s", v.Project, v.Version, v.Release, v.BaseName)
		fileName := baseName + "." + v.Type + ".sql"
		mainPath := filepath.Join(MigrationDir, fileName)
		mainKey := v.BaseName + "|" + v.Type
		mainMeta, exists := mainMap[mainKey]
		if !exists {
			// new file
			copyFileWithMeta(v.Path, mainPath, v.Path)
			copyIncludes(v.Path, filepath.Dir(mainPath))
			fmt.Printf("[add] %s\n", fileName)
			totalAdded++
		} else if mainMeta.MD5 != v.MD5 && v.MD5 != "" {
			// update file
			copyFileWithMeta(v.Path, mainPath, v.Path)
			copyIncludes(v.Path, filepath.Dir(mainPath))
			fmt.Printf("[update] %s\n", fileName)
			totalUpdated++
		}
	}

	// delete missing
	// gathering all keys from subMap for search
	subKeys := make(map[string]struct{})
	for _, v := range subMap {
		key := v.BaseName + "|" + v.Type
		subKeys[key] = struct{}{}
	}
	for k, v := range mainMap {
		if _, ok := subKeys[k]; !ok {
			os.Remove(v.Path)
			fmt.Printf("[delete] %s\n", filepath.Base(v.Path))
			totalDeleted++
		}
	}

	fmt.Printf("[ok] collected: added %d, updated %d, deleted %d file(s)\n", totalAdded, totalUpdated, totalDeleted)
	// validation after collecting
	check()
}

// copies file and adds metainfo about its origin
func copyFileWithMeta(src, dst, metaSrc string) error {
	input, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	// add info in the beginning
	meta := fmt.Sprintf("#migration: %s;%s\n", metaSrc, fileMD5(src))
	output := append([]byte(meta), input...)
	return os.WriteFile(dst, output, 0644)
}

func fileMD5(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	h := md5.New()
	if _, err := io.Copy(h, f); err != nil {
		return ""
	}
	return fmt.Sprintf("%x", h.Sum(nil))
}

// copies include-files, if there are no in the targetDir
func copyIncludes(sqlFile, targetDir string) {
	includes, _ := findIncludes(sqlFile, nil)
	for _, inc := range includes {
		incSrc := filepath.Join(filepath.Dir(sqlFile), inc)
		incDst := filepath.Join(targetDir, inc)
		if _, err := os.Stat(incDst); os.IsNotExist(err) {
			os.MkdirAll(filepath.Dir(incDst), 0755)
			input, err := os.ReadFile(incSrc)
			if err == nil {
				os.WriteFile(incDst, input, 0644)
			}
		}
	}
}

func check() {
	// t0 := time.Now()
	var errors []string
	errCh := make(chan string, 10000)
	wrongFiles := 0

	// main
	errs, wrong := validateMigrationFilenames(MigrationDir)
	for _, e := range errs {
		errCh <- e
	}
	wrongFiles += wrong
	mainUp, mainDown, err := findMigrationFiles(MigrationDir)
	if err != nil {
		errCh <- fmt.Sprintf("Error finding migration files: %v", err)
	}

	// submodules
	submodules, err := getSubmodules()
	if err != nil {
		errCh <- fmt.Sprintf("Error getting submodules: %v", err)
	}
	missed := []string{}
	for _, sub := range submodules {
		if _, err := findDescribeScript(sub); err != nil {
			errCh <- fmt.Sprintf("ERROR: %v", err)
		}
		subMigDir := filepath.Join(sub, "migrations")
		errs, wrong := validateMigrationFilenames(subMigDir)
		for _, e := range errs {
			errCh <- e
		}
		wrongFiles += wrong

		subUp, subDown, _ := findMigrationFiles(subMigDir)
		for key, upPath := range subUp {
			if _, ok := mainUp[key]; !ok {
				missed = append(missed, upPath)
			}
			if mainPath, ok := mainUp[key]; ok {
				_, mainMD5 := parseMigrationMeta(mainPath)
				_, subMD5 := parseMigrationMeta(upPath)
				if mainMD5 != "" && subMD5 != "" && mainMD5 != subMD5 {
					errCh <- fmt.Sprintf("ERROR: migration meta mismatch for %s: main md5=%s, submodule md5=%s", key+".up.sql", mainMD5, subMD5)
				}
			}
		}
		for key, downPath := range subDown {
			if _, ok := mainDown[key]; !ok {
				missed = append(missed, downPath)
			}
			if mainPath, ok := mainDown[key]; ok {
				_, mainMD5 := parseMigrationMeta(mainPath)
				_, subMD5 := parseMigrationMeta(downPath)
				if mainMD5 != "" && subMD5 != "" && mainMD5 != subMD5 {
					errCh <- fmt.Sprintf("ERROR: migration meta mismatch for %s: main md5=%s, submodule md5=%s", key+".down.sql", mainMD5, subMD5)
				}
			}
		}
	}

	// check having a piar up - down.sql
	wrongPairs := make([]string, 0, len(mainUp)+len(mainDown))
	pairWg := sync.WaitGroup{}
	pairCh := make(chan string, len(mainUp)+len(mainDown))
	for key := range mainUp {
		pairWg.Add(1)
		go func(key string) {
			defer pairWg.Done()
			if _, ok := mainDown[key]; !ok {
				pairCh <- key + ".up.sql (no pair .down.sql)"
			}
		}(key)
	}
	for key := range mainDown {
		pairWg.Add(1)
		go func(key string) {
			defer pairWg.Done()
			if _, ok := mainUp[key]; !ok {
				pairCh <- key + ".down.sql (no pair .up.sql)"
			}
		}(key)
	}
	pairWg.Wait()
	close(pairCh)
	for p := range pairCh {
		wrongPairs = append(wrongPairs, p)
	}

	// check include files
	missingIncludes := []string{}
	incWg := sync.WaitGroup{}
	incCh := make(chan string, len(mainUp)+len(mainDown))
	for _, upPath := range mainUp {
		incWg.Add(1)
		go func(upPath string) {
			defer incWg.Done()
			includes, _ := findIncludes(upPath, nil)
			for _, inc := range includes {
				incPath := filepath.Join(filepath.Dir(upPath), inc)
				if _, err := os.Stat(incPath); os.IsNotExist(err) {
					incCh <- incPath
					wrongFiles++
				}
			}
		}(upPath)
	}
	for _, downPath := range mainDown {
		incWg.Add(1)
		go func(downPath string) {
			defer incWg.Done()
			includes, _ := findIncludes(downPath, nil)
			for _, inc := range includes {
				incPath := filepath.Join(filepath.Dir(downPath), inc)
				if _, err := os.Stat(incPath); os.IsNotExist(err) {
					incCh <- incPath
					wrongFiles++
				}
			}
		}(downPath)
	}
	incWg.Wait()
	close(incCh)
	for inc := range incCh {
		missingIncludes = append(missingIncludes, inc)
	}

	close(errCh)
	for e := range errCh {
		errors = append(errors, e)
	}

	// output errors
	if wrongFiles > 0 {
		errors = append(errors, fmt.Sprintf("ERROR: there is wrong files %d, fix them", wrongFiles))
	}
	if len(errors) > 0 {
		for _, e := range errors {
			fmt.Println(e)
		}
		// fmt.Printf("Время выполнения check: %v\n", time.Since(t0))
		os.Exit(1)
	}
	if len(missed) > 0 {
		fmt.Println("unregistered migrations (only in submodules):")
		for _, m := range missed {
			fmt.Println("  ", m)
		}
		fmt.Println("use: scripts/migration.go collect")
		// fmt.Printf("Время выполнения check: %v\n", time.Since(t0))
		os.Exit(1)
	}
	if len(wrongPairs) > 0 {
		fmt.Println("wrong pairs:")
		for _, w := range wrongPairs {
			fmt.Println("  ", w)
		}
		// fmt.Printf("Время выполнения check: %v\n", time.Since(t0))
		os.Exit(1)
	}
	if len(missingIncludes) > 0 {
		fmt.Println("missing include-files:")
		for _, inc := range missingIncludes {
			fmt.Println("  ", inc)
		}
		// fmt.Printf("Время выполнения check: %v\n", time.Since(t0))
		os.Exit(1)
	}
	fmt.Println("[ok] Migrations are correct. No unregistered found.")
	// fmt.Printf("Время выполнения check: %v\n", time.Since(t0))
}

func getSubmodules() ([]string, error) {
	cmd := exec.Command("git", "submodule")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get git submodules: %v", err)
	}
	lines := strings.Split(string(output), "\n")
	submodules := []string{}
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			submodules = append(submodules, fields[1])
		}
	}
	return submodules, nil
}

func findMigrationFiles(root string) (map[string]string, map[string]string, error) {
	upFiles := make(map[string]string)
	downFiles := make(map[string]string) //  key: clean name; value: path
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		if strings.HasSuffix(info.Name(), ".up.sql") {
			key := strings.TrimSuffix(info.Name(), ".up.sql")
			upFiles[key] = path
		} else if strings.HasSuffix(info.Name(), ".down.sql") {
			key := strings.TrimSuffix(info.Name(), ".down.sql")
			downFiles[key] = path
		}
		return nil
	})
	if err != nil {
		return nil, nil, err
	}
	return upFiles, downFiles, nil
}

func findDescribeScript(submodulePath string) (string, error) {
	paths := []string{
		filepath.Join(submodulePath, "describe.sh"),
		filepath.Join(submodulePath, "scripts", "describe.sh"),
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("submodule %s has no describe script", submodulePath)
}

func validateMigrationFilenames(dir string) ([]string, int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist((err)) {
			return nil, 0
		}
		return []string{fmt.Sprintf("ERROR: failed to read dir %s: %v", dir, err)}, 0
	}
	var errs []string
	count := 0
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasSuffix(name, ".up.sql") && !strings.HasSuffix(name, ".down.sql") {
			errs = append(errs, fmt.Sprintf("ERROR: %s wrong file name suffix expect .up.sql or .down.sql", name))
			count++
		}
	}
	return errs, count
}

func findIncludes(filePath string, visited map[string]struct{}) ([]string, error) {
	includes := []string{}
	if visited == nil {
		visited = make(map[string]struct{})
	}
	if _, ok := visited[filePath]; ok {
		return includes, nil
	}
	visited[filePath] = struct{}{}
	content, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "@") {
			inc := strings.TrimPrefix(line, "@")
			inc = strings.Split(inc, ";")[0] // убрать ; если есть
			inc = strings.TrimSpace(inc)
			if inc != "" {
				if !strings.HasSuffix(inc, ".sql") {
					fmt.Printf("ERROR:   wrong include @%s in %s\n", inc, filePath)
					continue
				}
				incPath := filepath.Join(filepath.Dir(filePath), inc)
				if _, err := os.Stat(incPath); os.IsNotExist(err) {
					fmt.Printf("ERROR:   wrong include @%s in %s\n", inc, filePath)
					continue
				}
				includes = append(includes, inc)
				recInc, _ := findIncludes(incPath, visited)
				includes = append(includes, recInc...)
			}
		}
	}
	return includes, nil
}

func parseMigrationMeta(filePath string) (string, string) {
	content, err := os.ReadFile(filePath)
	if err != nil {
		return "", ""
	}
	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "#migration:") {
			parts := strings.SplitN(strings.TrimSpace(line), ":", 2)
			if len(parts) == 2 {
				meta := strings.TrimSpace(parts[1])
				metaParts := strings.Split(meta, ";")
				if len(metaParts) == 2 {
					return metaParts[0], metaParts[1]
				}
			}
		}
	}
	return "", ""
}
