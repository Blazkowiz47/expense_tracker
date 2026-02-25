package expense

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestCreateAndListWithFilter(t *testing.T) {
	repo := NewInMemoryRepository()
	svc := NewService(repo)

	ids := []string{"e1", "e2", "e3"}
	i := 0
	svc.idGenerator = func() string {
		id := ids[i]
		i++
		return id
	}
	svc.now = func() time.Time { return time.Date(2026, 1, 20, 10, 0, 0, 0, time.UTC) }

	ctx := context.Background()
	_, err := svc.Create(ctx, "uid-1", CreateExpenseInput{Amount: 100, Category: "Groceries", Description: "a", Date: time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("create #1 failed: %v", err)
	}
	_, err = svc.Create(ctx, "uid-1", CreateExpenseInput{Amount: 50, Category: "Transport", Description: "b", Date: time.Date(2026, 1, 5, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("create #2 failed: %v", err)
	}
	_, err = svc.Create(ctx, "uid-1", CreateExpenseInput{Amount: 25, Category: "Groceries", Description: "c", Date: time.Date(2026, 1, 15, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("create #3 failed: %v", err)
	}

	items, err := svc.List(ctx, "uid-1", ListFilter{Category: "groceries", Page: 1, Limit: 10})
	if err != nil {
		t.Fatalf("list failed: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
	if items[0].ID != "e3" || items[1].ID != "e1" {
		t.Fatalf("unexpected list order: %#v", items)
	}
}

func TestUpdateForbiddenForOtherUser(t *testing.T) {
	repo := NewInMemoryRepository()
	svc := NewService(repo)
	svc.idGenerator = func() string { return "e1" }
	svc.now = func() time.Time { return time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC) }

	ctx := context.Background()
	_, err := svc.Create(ctx, "owner", CreateExpenseInput{Amount: 100, Category: "Food", Date: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("create failed: %v", err)
	}

	_, err = svc.Update(ctx, "intruder", "e1", UpdateExpenseInput{Amount: 120, Category: "Food", Date: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestDeleteNotFound(t *testing.T) {
	repo := NewInMemoryRepository()
	svc := NewService(repo)

	err := svc.Delete(context.Background(), "uid-1", "missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
