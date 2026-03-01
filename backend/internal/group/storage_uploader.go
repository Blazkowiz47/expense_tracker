package group

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/google/uuid"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
)

type AttachmentUploader interface {
	UploadGroupAttachment(ctx context.Context, input AttachmentUploadInput) (string, error)
}

type AttachmentUploadInput struct {
	GroupID     string
	ExpenseID   string
	UploaderUID string
	FileName    string
	ContentType string
	Bytes       []byte
}

type FirebaseAttachmentUploader struct {
	client           *storage.Client
	bucketCandidates []string
}

func NewFirebaseAttachmentUploader(
	ctx context.Context,
	projectID string,
	credentialsFile string,
	bucket string,
) (*FirebaseAttachmentUploader, error) {
	if strings.TrimSpace(projectID) == "" {
		return nil, errors.New("firebase project id is required for storage uploader")
	}
	bucket = strings.TrimSpace(bucket)
	bucketCandidates := make([]string, 0, 2)
	seen := map[string]struct{}{}
	addBucket := func(value string) {
		value = strings.TrimSpace(value)
		if value == "" {
			return
		}
		if _, ok := seen[value]; ok {
			return
		}
		seen[value] = struct{}{}
		bucketCandidates = append(bucketCandidates, value)
	}
	addBucket(bucket)
	addBucket(projectID + ".firebasestorage.app")
	addBucket(projectID + ".appspot.com")

	var (
		client *storage.Client
		err    error
	)
	if strings.TrimSpace(credentialsFile) != "" {
		client, err = storage.NewClient(ctx, option.WithCredentialsFile(credentialsFile))
	} else {
		client, err = storage.NewClient(ctx)
	}
	if err != nil {
		return nil, fmt.Errorf("create storage client: %w", err)
	}
	return &FirebaseAttachmentUploader{
		client:           client,
		bucketCandidates: bucketCandidates,
	}, nil
}

func (u *FirebaseAttachmentUploader) Close() error {
	return u.client.Close()
}

func (u *FirebaseAttachmentUploader) UploadGroupAttachment(
	ctx context.Context,
	input AttachmentUploadInput,
) (string, error) {
	if len(input.Bytes) == 0 {
		return "", errors.New("attachment is empty")
	}
	objectPath := fmt.Sprintf(
		"groups/%s/%s/%s",
		strings.TrimSpace(input.GroupID),
		strings.TrimSpace(input.ExpenseID),
		uuid.NewString(),
	)
	var lastErr error
	for _, bucket := range u.bucketCandidates {
		downloadToken := uuid.NewString()
		writer := u.client.Bucket(bucket).Object(objectPath).NewWriter(ctx)
		writer.ContentType = strings.TrimSpace(input.ContentType)
		if writer.ContentType == "" {
			writer.ContentType = "application/octet-stream"
		}
		writer.Metadata = map[string]string{
			"firebaseStorageDownloadTokens": downloadToken,
			"originalFileName":              strings.TrimSpace(input.FileName),
		}
		if _, err := writer.Write(input.Bytes); err != nil {
			_ = writer.Close()
			lastErr = fmt.Errorf("write attachment to storage: %w", err)
			continue
		}
		if err := writer.Close(); err != nil {
			lastErr = fmt.Errorf("close storage writer: %w", err)
			if isNotFoundBucketError(err) {
				continue
			}
			return "", lastErr
		}

		escaped := url.QueryEscape(objectPath)
		downloadURL := fmt.Sprintf(
			"https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
			bucket,
			escaped,
			downloadToken,
		)
		return downloadURL, nil
	}
	if lastErr == nil {
		lastErr = errors.New("storage bucket candidates were empty")
	}
	return "", fmt.Errorf(
		"attachment upload failed for buckets %v: %w",
		u.bucketCandidates,
		lastErr,
	)
}

func isNotFoundBucketError(err error) bool {
	var apiErr *googleapi.Error
	if errors.As(err, &apiErr) {
		return apiErr.Code == 404
	}
	return strings.Contains(strings.ToLower(err.Error()), "bucket does not exist")
}
