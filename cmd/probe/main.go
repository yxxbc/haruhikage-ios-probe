package main

import (
	"fmt"
	"strings"
)

func main() {
	// What a real search answer looks like for a title with an odd glyph.
	name := "歌\t名"
	fmt.Printf("name has tab: %v\n", strings.Contains(name, "\t"))
	line := fmt.Sprintf("%d\t%s\t%s\t%s\t%s", 1, name, "人", "专辑", "封面")
	fmt.Printf("fields after split: %d\n", len(strings.Split(line, "\t")))
}
