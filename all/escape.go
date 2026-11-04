package all

import "strings"

// The fields of a line are joined with tabs, so a field that holds a tab or
// a line break would split the line into more fields than it has — a song
// whose title has a tab would show its artist as its album. Rare, and real:
// a title can hold anything the service allows.
//
// So each field is escaped on the way out and read back on the way in, with
// the two characters a line is made of.

// esc escapes the fields' separators, and the escape itself so that the
// reading is unambiguous.
func esc(s string) string {
	if !strings.ContainsAny(s, "\\\t\n\r") {
		return s
	}
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '\\':
			b.WriteString(`\\`)
		case '\t':
			b.WriteString(`\t`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// row joins fields with tabs, each escaped: the shape every list crosses
// in.
func row(fields ...string) string {
	out := make([]string, len(fields))
	for i, f := range fields {
		out[i] = esc(f)
	}
	return strings.Join(out, "\t")
}
