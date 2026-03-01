package group

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/google/uuid"
	"google.golang.org/api/option"
)

type AttachmentUploader interface {
	UploadGroupAttachment(ctx context.Context, input AttachmentUploadInput) (string, error)
}

type AttachmentUploadInput struct {
	GroupID     string
	UploaderUID string
	FileName    string
	ContentType string
	Bytes       []byte
}

type FirebaseAttachmentUploader struct {
	client *storage.Client
	bucket string
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
	if bucket == "" {
		bucket = projectID + ".appspot.com"
	}

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
	return &FirebaseAttachmentUploader{client: client, bucket: bucket}, nil
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
		"groups/%s/attachments/%s/%s",
		strings.TrimSpace(input.GroupID),
		strings.TrimSpace(input.UploaderUID),
		uuid.NewString(),
	)
	downloadToken := uuid.NewString()
	writer := u.client.Bucket(u.bucket).Object(objectPath).NewWriter(ctx)
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
		return "", fmt.Errorf("write attachment to storage: %w", err)
	}
	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("close storage writer: %w", err)
	}

	escaped := url.QueryEscape(objectPath)
	downloadURL := fmt.Sprintf(
		"https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
		u.bucket,
		escaped,
		downloadToken,
	)
	return downloadURL, nil
}
