package group

import "time"

type GroupType string

const (
	GroupTypeSplit  GroupType = "split"
	GroupTypeFamily GroupType = "family"
)

type Group struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	GroupType   GroupType         `json:"groupType"`
	CreatedBy   string            `json:"createdBy"`
	MemberUIDs  []string          `json:"memberUids"`
	MemberCount int               `json:"memberCount"`
	DisplayData *GroupDisplayData `json:"displayData,omitempty"`
	CreatedAt   time.Time         `json:"createdAt"`
	UpdatedAt   time.Time         `json:"updatedAt"`
}

type GroupDisplayData struct {
	ExpenseCount     int                           `json:"expenseCount"`
	TotalSpend       float64                       `json:"totalSpend"`
	TotalAttachments int                           `json:"totalAttachments"`
	AttachmentCounts map[string]int                `json:"attachmentCounts,omitempty"`
	MemberBalances   map[string]GroupMemberBalance `json:"memberBalances,omitempty"`
	UpdatedAt        time.Time                     `json:"updatedAt"`
}

type GroupMemberBalance struct {
	Owes float64 `json:"owes"`
	Owed float64 `json:"owed"`
	Net  float64 `json:"net"`
}

type GroupExpense struct {
	ID          string    `json:"id"`
	GroupID     string    `json:"groupId"`
	CreatedBy   string    `json:"createdBy"`
	UpdatedBy   string    `json:"updatedBy"`
	PaidBy      string    `json:"paidBy"`
	SplitMode   string    `json:"splitMode"`
	SplitWith   []string  `json:"splitWith"`
	Amount      float64   `json:"amount"`
	Description string    `json:"description"`
	Attachments []string  `json:"attachments"`
	Date        time.Time `json:"date"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

type GroupMember struct {
	UID         string `json:"uid"`
	DisplayName string `json:"displayName"`
	Email       string `json:"email"`
	Phone       string `json:"phone"`
}
