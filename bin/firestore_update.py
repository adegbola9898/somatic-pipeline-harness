#!/usr/bin/env python3

from datetime import datetime, timezone
import argparse
from google.cloud import firestore


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--project", required=True)
    parser.add_argument("--collection", required=True)
    parser.add_argument("--run-id", required=True)

    parser.add_argument("--status", required=True)
    parser.add_argument("--metadata-finalized", choices=["true", "false"], default="false")

    parser.add_argument("--failed-step", default=None)
    parser.add_argument("--exit-code", type=int, default=None)
    parser.add_argument("--failure-category", default=None)
    parser.add_argument("--failure-reason", default=None)

    args = parser.parse_args()

    client = firestore.Client(project=args.project)
    doc = client.collection(args.collection).document(args.run_id)

    payload = {
        "status": args.status,
        "metadata_finalized": args.metadata_finalized == "true",
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }

    if args.failed_step:
        payload["failed_step"] = args.failed_step

    if args.exit_code is not None:
        payload["exit_code"] = args.exit_code

    if args.failure_category:
        payload["failure_category"] = args.failure_category

    if args.failure_reason:
        payload["failure_reason"] = args.failure_reason

    doc.set(payload, merge=True)

    print("firestore_status_updated", args.status)


if __name__ == "__main__":
    main()
