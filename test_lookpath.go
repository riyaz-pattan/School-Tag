package main
import (
	"fmt"
	"os"
	"os/exec"
)
func main() {
	fmt.Println("PATH:", os.Getenv("PATH"))
	path, err := exec.LookPath("npx")
	if err != nil {
		fmt.Println("Error:", err)
	} else {
		fmt.Println("Found at:", path)
	}
}
