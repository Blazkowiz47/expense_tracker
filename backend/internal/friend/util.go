package friend

import (
	"strings"
	"unicode"
)

func normalizeQuery(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if strings.Contains(trimmed, "@") {
		return strings.ToLower(trimmed)
	}
	return normalizePhone(trimmed)
}

func normalizePhone(raw string) string {
	if raw == "" {
		return ""
	}

	var b strings.Builder
	for i, r := range raw {
		if r == '+' && i == 0 {
			b.WriteRune(r)
			continue
		}
		if unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}
