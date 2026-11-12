"""Verify an actual simulator update by durable store and record identity.

Apple TN2285 explicitly says the absolute application-container path may change.
This helper reads only the synthetic CI database, including its committed WAL.
"""
from pathlib import Path
from contextlib import closing
import argparse
import hashlib
import json
import plistlib
import sqlite3
import uuid

BASELINE = "5800cd924066c81d4096efbb50f5b0fd7141fdc9"
RELATIVE_DB = "Library/Application Support/LifeOS/LifeOS-v1.sqlite"


def read_store(container):
    container = Path(container).resolve(strict=True)
    database = container / RELATIVE_DB
    assert database.is_file() and not database.is_symlink(), "Missing durable database"
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as connection:
        connection.execute("PRAGMA query_only=ON")
        connection.execute("BEGIN")
        metadata_rows = connection.execute("SELECT Z_PLIST FROM Z_METADATA").fetchall()
        assert len(metadata_rows) == 1, "Ambiguous Core Data metadata"
        metadata = plistlib.loads(bytes(metadata_rows[0][0]))
        assert metadata.get("NSStoreType") == "SQLite"
        store_uuid = str(uuid.UUID(metadata["NSStoreUUID"]))
        rows = connection.execute(
            "SELECT Z_PK, ZPAYLOAD FROM ZLIFEOSSNAPSHOT WHERE ZKEY = ?", ("current",)
        ).fetchall()
        assert len(rows) == 1, "Missing or ambiguous current snapshot"
        raw = bytes(rows[0][1])
        assert len(raw) < 128 * 1024 * 1024
        snapshot = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        media = {}
        for key, value in connection.execute("SELECT ZKEY, ZPAYLOAD FROM ZLIFEOSSNAPSHOT WHERE ZKEY LIKE 'media:%'"):
            assert key not in media
            media[key] = {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
    return {"store_uuid": store_uuid, "snapshot_row_pk": rows[0][0],
            "snapshot": snapshot, "payload_sha256": hashlib.sha256(raw).hexdigest(), "media": media}


def indexed(rows):
    assert isinstance(rows, list)
    result = {str(uuid.UUID(row["id"])): row for row in rows}
    assert len(result) == len(rows), "Duplicate record identity"
    return result


def fields_preserved(before, after):
    for key, value in before.items():
        assert key in after, "A baseline field disappeared: " + key
        observed = after[key]
        if key in {"createdAt", "completedAt", "dueAt", "at"} and isinstance(value, (int, float)):
            assert type(observed) in (int, float) and abs(observed - value) <= 1.0, "A baseline date changed"
        else:
            assert observed == value, "A baseline field changed: " + key


def capture(container):
    current = read_store(container)
    snapshot = current["snapshot"]
    assert snapshot["schemaVersion"] == 1
    tasks = snapshot["tasks"]
    assert len(tasks) == 1 and tasks[0]["title"].startswith("手机任务-"), "Baseline UI fixture was not created"
    indexed(tasks)
    assert all(not snapshot[key] for key in ["plans", "sessions", "goals", "measurements", "reviews", "places", "routes"])
    assert snapshot["pendingChanges"], "Baseline journal is missing"
    indexed(snapshot["pendingChanges"])
    return {"schema": "dayisle-upgrade-baseline/v1", "baseline_source": BASELINE,
            "relative_database_path": RELATIVE_DB, "snapshot_schema_version": 1,
            "store_uuid": current["store_uuid"], "snapshot_row_pk": current["snapshot_row_pk"],
            "payload_sha256": current["payload_sha256"], "tasks": tasks,
            "pending_changes": snapshot["pendingChanges"], "media": current["media"],
            "synthetic_ci_data_only": True}


def verify(before, container, path_unchanged):
    assert before["schema"] == "dayisle-upgrade-baseline/v1" and before["baseline_source"] == BASELINE
    current = read_store(container)
    assert current["store_uuid"] == before["store_uuid"], "Persistent store identity changed"
    assert current["snapshot_row_pk"] == before["snapshot_row_pk"], "Persistent snapshot identity changed"
    snapshot = current["snapshot"]
    assert snapshot["schemaVersion"] == 2, "V2 snapshot was not persisted"
    for field, old_rows in [("tasks", before["tasks"]), ("pendingChanges", before["pending_changes"])]:
        actual = indexed(snapshot[field])
        for identifier, old in indexed(old_rows).items():
            assert identifier in actual, "A baseline record disappeared"
            fields_preserved(old, actual[identifier])
    for key, expected in before["media"].items():
        assert current["media"].get(key) == expected, "Baseline media changed"
    return {"schema": "dayisle-native-upgrade-check/v2", "baseline_source": BASELINE,
            "new_install_over_baseline": True, "container_path_unchanged": bool(path_unchanged),
            "core_data_store_uuid_unchanged": True, "snapshot_object_identity_unchanged": True,
            "baseline_task_id_and_content_preserved": True, "baseline_pending_changes_preserved": True,
            "baseline_media_bytes_preserved": True, "baseline_task_count": len(before["tasks"]),
            "baseline_schema": 1, "upgraded_schema": 2, "synthetic_ci_data_only": True,
            "legacy_task_UI_gate": "passed by required XCTest", "physical_iphone_verified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["capture", "verify"])
    parser.add_argument("--container-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--before", type=Path)
    parser.add_argument("--baseline-container-file", type=Path)
    args = parser.parse_args()
    container = args.container_file.read_text().strip()
    if args.mode == "capture":
        report = capture(container)
    else:
        assert args.before and args.baseline_container_file
        before = json.loads(args.before.read_text())
        report = verify(before, container, container == args.baseline_container_file.read_text().strip())
    args.output.write_text(json.dumps(report, ensure_ascii=True, indent=2))
    print(json.dumps({"upgrade_phase": args.mode, "result": "passed", "synthetic_ci_data_only": True}))


if __name__ == "__main__":
    main()
