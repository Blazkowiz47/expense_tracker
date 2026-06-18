#!/usr/bin/env python3
"""Copy the local expense-tracker MongoDB database to a remote MongoDB.

Defaults are intentionally conservative:
- source is local dev MongoDB
- target URI must be supplied through env
- dry-run unless --execute is passed
- target collections are not dropped unless --replace-target is passed
"""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Iterable
from dataclasses import dataclass

from pymongo import MongoClient, ReplaceOne
from pymongo.errors import BulkWriteError, PyMongoError


DEFAULT_SOURCE_URI = "mongodb://127.0.0.1:27017"
DEFAULT_SOURCE_DB = "expense_tracker_local"
DEFAULT_TARGET_DB = "expense_tracker_prod"


@dataclass(frozen=True)
class SyncConfig:
    source_uri: str
    source_db: str
    target_uri: str
    target_db: str
    execute: bool
    replace_target: bool
    collections: tuple[str, ...]
    batch_size: int


def env_first(*names: str) -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return ""


def parse_args(argv: list[str]) -> SyncConfig:
    parser = argparse.ArgumentParser(
        description="Sync local expense_tracker_local Mongo data to a remote MongoDB database."
    )
    parser.add_argument(
        "--source-uri",
        default=os.getenv("SOURCE_MONGO_URI", DEFAULT_SOURCE_URI),
        help="Source Mongo URI. Defaults to local MongoDB.",
    )
    parser.add_argument(
        "--source-db",
        default=os.getenv("SOURCE_MONGO_DB", DEFAULT_SOURCE_DB),
        help="Source database name.",
    )
    parser.add_argument(
        "--target-uri",
        default=env_first("TARGET_MONGO_URI", "REMOTE_MONGO_URI", "ATLAS_MONGO_URI"),
        help="Target Mongo URI. Prefer env TARGET_MONGO_URI.",
    )
    parser.add_argument(
        "--target-db",
        default=env_first("TARGET_MONGO_DB", "REMOTE_MONGO_DB", "ATLAS_MONGO_DB") or DEFAULT_TARGET_DB,
        help="Target database name.",
    )
    parser.add_argument(
        "--collections",
        nargs="*",
        default=(),
        help="Optional collection names to sync. Defaults to all non-system source collections.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=500,
        help="Bulk write batch size.",
    )
    parser.add_argument(
        "--replace-target",
        action="store_true",
        help="Drop target collections before copying. Use this for a first full migration.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Actually write target data. Without this, only prints a dry-run plan.",
    )
    args = parser.parse_args(argv)
    if not args.target_uri:
        parser.error("target URI is required. Set TARGET_MONGO_URI or pass --target-uri.")
    if args.batch_size < 1:
        parser.error("--batch-size must be positive.")
    return SyncConfig(
        source_uri=args.source_uri,
        source_db=args.source_db,
        target_uri=args.target_uri,
        target_db=args.target_db,
        execute=args.execute,
        replace_target=args.replace_target,
        collections=tuple(args.collections),
        batch_size=args.batch_size,
    )


def redact_uri(uri: str) -> str:
    if "://" not in uri or "@" not in uri:
        return uri
    scheme, rest = uri.split("://", 1)
    _, host = rest.split("@", 1)
    return f"{scheme}://<credentials>@{host}"


def batched(items: Iterable[dict], size: int) -> Iterable[list[dict]]:
    batch: list[dict] = []
    for item in items:
        batch.append(item)
        if len(batch) >= size:
            yield batch
            batch = []
    if batch:
        yield batch


def collection_names(db) -> tuple[str, ...]:
    return tuple(
        name
        for name in sorted(db.list_collection_names())
        if not name.startswith("system.")
    )


def count_documents(db, collections: Iterable[str]) -> dict[str, int]:
    return {name: db[name].estimated_document_count() for name in collections}


def sync_collection(source_db, target_db, name: str, config: SyncConfig) -> int:
    source = source_db[name]
    target = target_db[name]
    if config.replace_target:
        target.drop()
    copied = 0
    for docs in batched(source.find({}), config.batch_size):
        operations = [
            ReplaceOne({"_id": doc["_id"]}, doc, upsert=True)
            for doc in docs
        ]
        if operations:
            target.bulk_write(operations, ordered=False)
            copied += len(operations)
    return copied


def main(argv: list[str]) -> int:
    config = parse_args(argv)
    source_client = MongoClient(config.source_uri, serverSelectionTimeoutMS=5000)
    target_client = MongoClient(config.target_uri, serverSelectionTimeoutMS=5000)
    source_db = source_client[config.source_db]
    target_db = target_client[config.target_db]

    try:
        source_client.admin.command("ping")
        target_client.admin.command("ping")
    except PyMongoError as exc:
        print(f"Mongo connection failed: {exc}", file=sys.stderr)
        return 2

    collections = config.collections or collection_names(source_db)
    source_counts = count_documents(source_db, collections)
    target_counts = count_documents(target_db, collections)

    print("Mongo sync plan")
    print(f"  source: {redact_uri(config.source_uri)} / {config.source_db}")
    print(f"  target: {redact_uri(config.target_uri)} / {config.target_db}")
    print(f"  mode: {'EXECUTE' if config.execute else 'DRY RUN'}")
    print(f"  replace target: {config.replace_target}")
    for name in collections:
        print(f"  - {name}: source={source_counts[name]} target={target_counts[name]}")

    if not config.execute:
        print("\nDry run only. Re-run with --execute to copy data.")
        return 0

    for name in collections:
        try:
            copied = sync_collection(source_db, target_db, name, config)
        except BulkWriteError as exc:
            print(f"Failed while syncing {name}: {exc.details}", file=sys.stderr)
            return 3
        print(f"synced {name}: {copied} documents")

    print("Sync complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
