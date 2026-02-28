package group

import "time"

type GroupType string

const (
	GroupTypeSplit  GroupType = "split"
	GroupTypeFamily GroupType = "family"
)

type Group struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	GroupType   GroupType `json:"groupType"`
	CreatedBy   string    `json:"createdBy"`
	MemberUIDs  []string  `json:"memberUids"`
	MemberCount int       `json:"memberCount"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

type GroupExpense struct {
	ID          string    `json:"id"`
	GroupID     string    `json:"groupId"`
	CreatedBy   string    `json:"createdBy"`
	Amount      float64   `json:"amount"`
	Description string    `json:"description"`
	Attachments []string  `json:"attachments"`
	Date        time.Time `json:"date"`
	CreatedAt   time.Time `json:"createdAt"`
}

type GroupMember struct {
	UID         string `json:"uid"`
	DisplayName string `json:"displayName"`
	Email       string `json:"email"`
	Phone       string `json:"phone"`
}
