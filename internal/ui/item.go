package ui

import (
	"fmt"
)

type item struct {
	title, desc string
}

func (i item) Title() string       { return i.title }
func (i item) Description() string { return i.desc }
func (i item) FilterValue() string { return i.title }

// String implements fmt.Stringer (optional but good for debugging)
func (i item) String() string { return fmt.Sprintf("%s: %s", i.title, i.desc) }
