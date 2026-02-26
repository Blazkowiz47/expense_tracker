package friend

import "context"

type Store interface {
	ResolveByEmailOrPhone(ctx context.Context, query string) (ResolveResult, error)
	AddFriendship(ctx context.Context, uid, friendUID string) error
	RemoveFriendship(ctx context.Context, uid, friendUID string) error
	ListFriends(ctx context.Context, uid string) ([]Friend, error)
}
