# Komga — Stale Task Queue After External File Changes

## Symptom

- Komga container CPU/log usage way higher than expected for what it does
- Web UI or `docker logs komga` shows a wall of errors like:
  ```
  java.nio.file.NoSuchFileException: /data/comics/upload/<some file>.cbz
      at ...BookLifecycle.hashAndPersist(BookLifecycle.kt:111)
      at ...TaskHandler.handleTask(TaskHandler.kt:149)
  ```
- Same book IDs keep failing over and over, for files you know are already deleted/moved

## Cause

Komga soft-deletes a book (sets `deletedDate`, keeps the DB row) when it notices the
file is gone from disk, but it doesn't clean up already-queued tasks (`HashBook`,
`AnalyzeBook`, ...) for that book. If a lot of files disappear at once — e.g. during
a manual reorg of the comics library (see `scripts/comics/HANDOVER.md`) — those tasks
just retry forever against paths that no longer exist, burning CPU and spamming logs
until the trash is emptied.

Confirmed this is exactly what happened here: 8,400+ `NoSuchFileException` errors and
~26k log lines/day from Komga alone, all pointing at comics that were already cleaned
up (Marauders, Wolverine, Uncanny X-Men, etc. — the Session 4 reorg series).

## Fix (one-time, when it happens again)

1. Web UI → **Settings → Libraries** → pick the affected library → **Empty Trash**.
   This purges the soft-deleted book rows and drains the stale task queue.
2. Verify in logs:
   ```bash
   docker logs komga --since 10m 2>&1 | grep -c NoSuchFileException
   ```
   Should drop to 0 within a few minutes.

## Prevention (per-library setting)

Komga has an `emptyTrashAfterScan` setting per library that auto-empties trash right
after every scan, so this can't build up a backlog again. It isn't obviously exposed
in this Komga version's UI — set it via the API instead.

**Trade-off:** with this on, any file that goes missing (including a file temporarily
unavailable during a move) is purged from Komga's DB on the very next scan, with no
recovery window. Only enable it on a library that isn't mid-reorg.

```bash
# Komga API key lives in scripts/comics/.env as KOMGA_API_KEY
API_KEY=$(grep -i "^KOMGA_API_KEY" /opt/homelab/scripts/comics/.env | cut -d= -f2)

# list libraries and their current setting
curl -s http://localhost:25600/api/v1/libraries -H "X-API-Key: $API_KEY" | python3 -m json.tool

# flip it on for a specific library (replace the ID)
curl -X PATCH http://localhost:25600/api/v1/libraries/<LIBRARY_ID> \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"emptyTrashAfterScan": true}'
```

Current state (2026-09-08):

| Library | ID             | `emptyTrashAfterScan` | Why |
|---------|----------------|------------------------|-----|
| Books   | `0QFH1XH7ZW3ZF` | `true`                 | Stable library, no ongoing reorg |
| Comics  | `0QFH29AVBW0VJ` | `false`                | Still has an unfinished manual reorg (see [[project_comics_library_cleanup]] / `scripts/comics/HANDOVER.md` Session 4) — a scan mid-move could silently delete records still needed. Flip on once that cleanup is finished. |

## Related

- `scripts/comics/HANDOVER.md` — Session 4 handover, the reorg that caused this batch of stale entries
- Never re-run `scripts/comics/organize_comics.py --execute` after manual reorg of the library — recreates duplicate files (separate issue, see that script's notes)
