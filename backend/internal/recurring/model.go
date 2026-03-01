package recurring

import "time"

type Template struct {
	ID          string    `json:"id"`
	UID         string    `json:"-"`
	Title       string    `json:"title"`
	Amount      float64   `json:"amount"`
	Category    string    `json:"category"`
	Frequency   string    `json:"frequency"`
	StartDate   time.Time `json:"startDate"`
	NextDueDate time.Time `json:"nextDueDate"`
	Active      bool      `json:"active"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}
