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
