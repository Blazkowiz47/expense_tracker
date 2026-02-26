package friend

type Friend struct {
	UID         string `json:"uid"`
	DisplayName string `json:"displayName"`
	Email       string `json:"email"`
}

type ResolveResult struct {
	Exists bool   `json:"exists"`
	UID    string `json:"uid,omitempty"`
}
