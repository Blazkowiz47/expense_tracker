package recurring

import (
	"context"
	"errors"
)

var ErrNotFound = errors.New("not found")

type Store interface {
	Create(ctx context.Context, template Template) (Template, error)
	ListByUser(ctx context.Context, uid string) ([]Template, error)
	Update(ctx context.Context, template Template) (Template, error)
}
