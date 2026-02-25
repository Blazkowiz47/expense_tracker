package expense

import "time"

// Expense is a user-owned expense record.
type Expense struct {
	ID          string    `json:"id"`
	UID         string    `json:"-"`
	Amount      float64   `json:"amount"`
	Category    string    `json:"category"`
	Description string    `json:"description"`
	Date        time.Time `json:"date"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// CreateExpenseInput is the request model used by service layer.
type CreateExpenseInput struct {
	Amount      float64
	Category    string
	Description string
	Date        time.Time
}

// UpdateExpenseInput is the request model used by service layer.
type UpdateExpenseInput struct {
	Amount      float64
	Category    string
	Description string
	Date        time.Time
}

// ListFilter controls expense listing.
type ListFilter struct {
	Page     int
	Limit    int
	Category string
	From     *time.Time
	To       *time.Time
}

// Analytics contains aggregate views for charting.
type Analytics struct {
	TotalAmount float64            `json:"totalAmount"`
	ByCategory  map[string]float64 `json:"byCategory"`
	ByMonth     map[string]float64 `json:"byMonth"`
}

type DashboardBalanceItem struct {
	Title      string `json:"title"`
	Subtitle   string `json:"subtitle"`
	AmountText string `json:"amountText"`
	Positive   bool   `json:"positive"`
}

type DashboardActivityItem struct {
	Title      string `json:"title"`
	Subtitle   string `json:"subtitle"`
	AmountText string `json:"amountText"`
	Positive   bool   `json:"positive"`
}

type DashboardSnapshot struct {
	OverallLabel      string                  `json:"overallLabel"`
	OverallAmountText string                  `json:"overallAmountText"`
	OverallPositive   bool                    `json:"overallPositive"`
	FriendItems       []DashboardBalanceItem  `json:"friendItems"`
	GroupItems        []DashboardBalanceItem  `json:"groupItems"`
	ActivityItems     []DashboardActivityItem `json:"activityItems"`
	AccountName       string                  `json:"accountName"`
	AccountEmail      string                  `json:"accountEmail"`
}
