# Instructions for agents

## Git

- Never run `git commit` or `git push` on your own initiative. Always ask first and wait for explicit confirmation on that specific commit/push, even if the user said something earlier that sounds like general authorization (e.g. "back this up to GitHub", "save this"). Propose what you'd commit and why, then wait.
- This repo is a **public** GitHub repo. Treat every push as visible to the world — an extra reason to confirm before pushing, not just before committing.

## Komga read lists (scripts/comics/krakoan_komga_readlists.py)

Verified against Komga's real API (`/v3/api-docs` for the schema, live
calls for behavior — not assumed):

- Komga series `metadata.title` mirrors Kapowarr's own folder naming
  exactly: `"House of X (2019)"`, same `"{Title} ({Year})"` format used
  throughout this project's own data. `GET /api/v1/series?search=<title>`
  is fuzzy (searching "X-Men" returns 29 loosely-related series) — always
  filter client-side for an exact `metadata.title` match, don't trust the
  first/only result.
- Within a matched series, `GET /api/v1/series/{id}/books` — each book's
  `metadata.numberSort` is a clean float matching the issue number (e.g.
  `4.0` for issue "4"). Reliable match key, no string-parsing needed.
- `POST /api/v1/readlists {name, bookIds: [...], ordered: true, summary}`
  creates an explicitly-ordered read list — `ordered: true` is the actual
  field name (confirmed via the OpenAPI schema, `ReadListCreationDto`).
  `PATCH /api/v1/readlists/{id}` with a fresh `bookIds` updates it in
  place (replaces the list, not additive) — safe to re-run any time
  a batch of downloads finishes, to fill in previously-missing entries.
- A reading-order entry with no downloaded file yet just has no matching
  book — skip it, not an error. Don't wait for 100% before building a
  list; build/update incrementally and it self-completes as downloads land.
- **Komga's `metadata.title` isn't always exactly `"{Title} ({Year})"`** —
  two different fallback patterns seen in this project, both silent (no
  error, just 0 results from an exact/prefix match):
  - An open-ended/ongoing series (no known end year) gets a trailing
    hyphen: `"Wolverine (2020-)"`, not `"Wolverine (2020)"`.
  - When Komga's own metadata-provider matching fails to identify a
    series, it falls back to the **raw folder name** as the title,
    which includes Kapowarr's `Volume NN` folder-naming segment:
    `"X-Men Unlimited Infinity Comic Volume 01 (2021)"`, not
    `"X-Men Unlimited Infinity Comic (2021)"`. This one cost ~130 issues
    (X-Men Unlimited Infinity Comic alone) from every read list they
    were needed in — a big, easily-missed silent gap.
  A plain substring/`.startswith()` prefix check is NOT safe against the
  second pattern either — short titles like `"X-Men"` are genuine
  substrings/prefix-words of unrelated series (`"X-Men Unlimited..."`,
  `"...X-Men/Black Knight..."`), so loosening to bare substring matching
  produces false positives. The correct pattern, anchored at the start:
  `^{title}( Volume \d+)? \({year}` (regex) — matches either the plain
  `"{title} ({year}"` prefix or the `"{title} Volume NN ({year}"`
  fallback, nothing else. Verified no ambiguity across all 150 series in
  this project with this exact pattern (only one genuine duplicate found —
  see next point, unrelated to this pattern).
- **A title can legitimately match more than one Komga series** — found
  `"New Mutants (2019)"` present as two separate Komga series entries with
  the identical title string (very likely the Italian Panini reprint vs.
  the real English series, a known confusion in this project's library —
  see `project_comics_library_cleanup` memory). Don't assume a single
  regex match means a single candidate; when there's more than one, prefer
  the one with the higher `booksCount` (the stray duplicate/reprint is
  typically much sparser than the real, actively-downloaded one) rather
  than silently picking whichever the API happened to return first.

## A file with no extractable year is not a safe match to anything

When cross-referencing `comics_holding` files against a target (series,
year) — matching by parsed series name plus a year tolerance (`if year and
abs(int(year) - int(target_year)) > 1: continue`) — a file whose year
**couldn't be parsed at all** (`year` is `None`/falsy) makes that
condition short-circuit false, so the `continue` never fires and the file
silently passes the check for *every* candidate year. Missing information
was being treated as "matches anything" instead of "reject, unverified" —
backwards.

Real, nearly-costly example: a `comics_holding/v1/` folder held the
*original 1991* X-Force ongoing (issues had no year in their filenames at
all, just `"X-Force V1 #26.X-Force.cbz"` etc.) which this bug matched
against the target Krakoan-era **2019** X-Force volume's missing-issue
list — ~40 false "matches" for issue numbers that happened to overlap.
Caught by pulling and viewing the actual cover art before importing
anything (same method as the Iron Man legacy-numbering catch): it was
plainly a September 1993 Liefeld-era cover ("Reignfire" storyline), not
2019 content. Of 58 total apparent matches, only 4 survived real
verification (via embedded `ComicInfo.xml` `<Volume>` tags, present on
some but not all files) — everything else was this bug.

Fix: a missing/unparseable year must **reject** the candidate, not pass it
through. If you want to still consider such files, that has to be a
deliberate, separately-flagged "needs manual verification" bucket — never
silently accepted. And prefer verifying via embedded `ComicInfo.xml`
(`<Series>`/`<Number>`/`<Volume>` tags, when present — check with `unzip -p
file.cbz ComicInfo.xml`) over filename parsing entirely where possible;
it's authoritative rather than inferred.

## Comparing comic archives for true duplicates

Two `.cbz`/`.cbr` files with the exact same **page content** can still have
different **full-file hashes** (SHA-256 of the whole archive) — the zip
container itself carries metadata (per-entry timestamps, compression
settings, comment field) that can differ even when every actual page image
inside is byte-identical. Observed in this project: Kapowarr appears to
re-package files on import, so a `comics_holding` copy of an issue and the
Kapowarr-managed copy of the *same* issue had matching file **size** but
mismatching full-file SHA-256 — full-file hashing alone would have wrongly
flagged 12/12 genuine duplicates as "not actually duplicates."

To verify two comic archives are really the same content, hash each
**page's image bytes individually** (open the zip, sort entry names, hash
each entry's content, compare the lists) rather than hashing the whole
file. Confirmed reliable: same entry names + same per-page hashes = truly
identical comic, safe to treat as a duplicate. A full-file size match alone
is a decent first-pass filter (cheap, catches the obvious cases) but file
size matching is not sufficient proof by itself either — verify at the
page level before deleting anything based on it.

## Komga auto-generates read lists from embedded ComicInfo.xml story arcs

If unexpected read lists appear with bracketed numbers in the name (e.g.
`"Fall of X [61126]"`, or a combined name like `"A [x], B [y]"` when a
single issue carries two story-arc tags) — that's Komga's own built-in
behavior, not something external or broken. Many scene-release scans
(GetComics/Zone-Empire etc.) embed `<StoryArc>`/`<StoryArcNumber>` tags in
`ComicInfo.xml`, and Komga auto-creates/updates a read list per unique
story-arc combination it finds during a scan.

No global setting disables this (checked `GET /api/v1/settings` — only
`deleteEmptyReadLists` etc., nothing story-arc-specific). The real control
is per-library: `importComicInfoReadList` (`GET`/`PATCH
/api/v1/libraries/{id}`) — set it `false` to stop Komga importing
ComicInfo.xml-sourced read lists entirely. Set `false` on the "Comics"
library (`0QFH29AVBW0VJ`) in this project since the user didn't want these
appearing. Existing auto-created ones from before the setting change don't
disappear on their own — delete them explicitly (`DELETE
/api/v1/readlists/{id}`) once.

## Kapowarr / ComicVine (scripts/comics/)

`scripts/comics/` is gitignored (working data/state files live there, not
meant to be tracked) — put anything meant to be shared or long-lived here
in this file instead, not a file under that directory.

Gotchas discovered working with Kapowarr and ComicVine's APIs:

### Kapowarr: `POST /api/volumes` monitoring defaults

The `monitor` field in the request body only sets the volume's own top-level
`monitored` flag — it does **not** control per-issue monitoring. If
`monitoring_scheme` is omitted, Kapowarr defaults it server-side to `"all"`,
so every issue in the volume ends up `monitored: true` regardless of what
`monitor` was set to.

If you want issue-level control (e.g. only monitor specific issues in a
volume, not the whole run), pass `"monitoring_scheme": "none"` explicitly in
the same POST body, or follow up with `PUT /api/volumes/<id>
{"monitoring_scheme": "none"}` before touching individual issues via `PUT
/api/issues/<id> {"monitored": true/false}`. Valid values: `all`, `missing`,
`none` (backend `MonitorScheme` enum, `/app/backend/base/definitions.py` in
the Kapowarr container).

Discovered adding the Krakoan-era reading order volumes: 141 volumes were
added with `monitor: false` intending zero issues monitored, but a dry-run
check showed every issue was actually monitored. Caught before any
auto-search/download ran.

**Second, worse gotcha from the same setup:** the volume-level `monitored`
flag isn't just cosmetic once you *do* have correct per-issue monitoring —
`auto_search(volume_id)` (backend `features/search_full.py`) checks
`volume_data.monitored` as a master switch and returns an empty result
**immediately, with no error or log line**, if it's `false`, regardless of
which issues are monitored. After fixing the per-issue monitoring above
(via `monitoring_scheme: "none"` + per-issue `PUT`s), the volume-level flag
was left at `false` — so 141 volumes' worth of auto-search triggers (671
issues) all silently no-opped in 0 seconds each. Took two failed search
runs and reading the `auto_search()` source to catch — the failure mode
looks identical to "genuinely no results," not an error. If you want
issue-level monitoring control, set `"monitoring_scheme": "none"` (or edit
issues individually) but leave/set the volume's own `"monitored": true` —
these two are independent switches, not one falling out of the other.

**Third instance, don't assume "pre-existing volumes are fine":** three of
the 8 volumes that were already in Kapowarr *before* this project started
(X-Men (2019), X-Men (2021), X-Men: Red (2022)) also had `monitored:
false` at the volume level — not something this project set, presumably
pre-existing state from however they'd been added originally. This wasn't
caught for a long time because the symptom is identical to "genuinely
searched, found nothing": `issues_downloaded` stuck at exactly 0 across
*multiple* retry passes, no errors anywhere. If a volume's count is stuck
at 0 despite repeated retries and the series is a real, well-covered
flagship title (unlikely to genuinely have zero results on the indexer),
check `GET /api/volumes/<id>` for `"monitored": false` directly — don't
assume the flag is only wrong on volumes *this* session added. Check every
volume you care about, regardless of its history.

### ComicVine rate limits are per-endpoint, not pooled

200 requests/hour, tracked separately per API path (`/volumes`, `/search`,
`/volume`, `/issue`). Check actual usage at the ComicVine account page
(logged-in comicvine.gamespot.com shows current usage per path and reset
time) rather than assuming a single shared budget — a heavy `/search` pass
doesn't touch the `/volume` budget used by Kapowarr's volume-add calls.

Kapowarr uses the same ComicVine API key as scripts in `scripts/comics/`
(see that directory's `.env`, `COMICVINE_API_KEY`), so Kapowarr's own
background tasks (`update_all`, RSS sync, etc.) and any direct scripts there
share the same per-endpoint buckets.

### Don't trust `issue_count >= needed_max` alone to confirm a volume match

When resolving an ambiguous title+year to a ComicVine volume (multiple
candidates, or CV's recorded `start_year` off by one from how a title is
conventionally referred to), checking that the matched volume's issue count
covers the highest issue number you need is necessary but **not sufficient**.

Real example: "Invincible Iron Man (2022)" auto-resolved to cv_id 95596
("Invincible Iron Man (2017)", 19 issues) because 19 >= needed_max 18 looked
plausible. Wrong — that volume's numbering runs 1-11 then jumps to Marvel's
"legacy numbering" gimmick (593-600), so the actually-needed issues #12-18
didn't exist there, while #4-11 existed only by numbering coincidence with
unrelated 2017-era content. The real match was a different volume entirely
(cv_id 146873), verified by checking that the specific needed issue numbers
had real sequential titles/dates in the expected era.

This trap is specific to Marvel/DC flagship or long-running titles that have
been relaunched or legacy-renumbered (Iron Man, Amazing Spider-Man, X-Men,
Avengers, etc. all have this history). For those, after picking a candidate,
spot-check 1-2 of the specific needed issue numbers via `GET
/api/issue/<id>` (`cover_date`/`description`) before trusting the match. A
"0 not_found" result after matching issue numbers is not proof of
correctness by itself if the wrong volume happens to have enough issues to
cover the range.

### `--full-sync` needs to re-check already-tried volumes, not just new ones

`krakoan_kapowarr_setup.py --trigger-search`'s one-time `search_triggered`
marker is meant to avoid redundant triggering *during the initial
rollout* — it is not a "never search this again" flag. A volume searched
once and found nothing at the time can absolutely have new content on the
indexer later (confirmed: Excalibur came up empty on its first search, had
2 real new matches sitting unclaimed hours later with nothing re-checking
it). A `--full-sync` that only calls `phase_trigger_search` will show "0
volumes to trigger" forever once the initial rollout is done and silently
do nothing useful — it needs a separate `phase_retry_incomplete` pass that
re-triggers `auto_search` for every volume that *currently* still has
missing needed issues, regardless of the one-time marker. This is safe to
re-run indefinitely — Kapowarr's `auto_search` only searches for
currently-missing monitored issues each time, so re-triggering an
already-complete or already-searched volume is a fast no-op, not wasted
duplicate work.

Scheduled via a real local cron job (`*/30 * * * *`, see crontab), not a
cloud-agent routine — the script needs `localhost:5656`/`localhost:25600`
(Kapowarr/Komga on this host), which a cloud agent session cannot reach.
A full `--full-sync` re-checking ~90 incomplete volumes took about an hour
in practice — much longer than the few-seconds-each estimate — so the
`krakoan_sync.lock` file (see `acquire_lock()`) matters here: at a 30-min
cron interval with an hour-long run, most ticks just skip because the
previous run is still going, and the next one starts immediately once it
finishes. That's fine and intentional — it's the fastest cadence
achievable without overlapping runs, not a bug.

### Kapowarr's blocklist over-blocks on transient errors — needs active reconciliation, not blind trust

`GetComicsPrepper.__fetch_page()` (`/app/backend/implementations/download_preppers/ddl/GetComics.py`
in the container) catches the *generic* `requests.RequestException` around
its page fetch and treats it identically to a permanently dead page
(`BlocklistReason.LINK_BROKEN`) — this catches `Timeout`, `ConnectionError`,
and any non-2xx response (Cloudflare interstitial, a transient 5xx), not
just genuine 404s. `NO_WORKING_LINKS` gets set the same way when every
mirror on a page fails just once. Neither distinguishes "genuinely gone"
from "hit a blip this one time" — confirmed on real data 2026-09-21: of
601 blocklisted links spot-checked with a direct HTTP GET, several came
back a clean 200. Once blocklisted, nothing in Kapowarr ever reconsiders
it, so `auto_search` permanently falls back to a worse/dead alternative
link and silently stalls that specific issue forever, indistinguishable
from genuine unavailability in the logs. Traced example: Invincible Iron
Man (2022) #10-13 and Uncanny Avengers (2023) #3-5 — the correct
"(2023)"-tagged GetComics posts were blocklisted, so every 30-min cron
cycle re-attempted a different, actually-broken fallback link and failed
with `NO_MATCHES`, identically, 44 times over 6 hours, with zero log
signal that anything was wrong.

**`GET /api/blocklist` also silently under-reports** — it hardcodes 50
results per page (`get_blocklist()` in `blocklist.py`, `LIMIT 50 OFFSET
?`) and the `offset` query param is a *page index*, not a row offset
(`offset * 50` internally). Calling it with no `offset` or with
`offset=50` (thinking that's "skip 50 rows") does not surface the rest —
you have to loop `offset=0,1,2,...` until a short/empty page. The real DB
can hold ~950 rows while a naive single GET shows only the newest 50, and
this looked like a genuine inconsistency (REST vs `docker exec sqlite3`
direct query disagreeing) until the pagination behavior was found in the
route source. `_get_all_blocklist_entries()` in
`krakoan_kapowarr_setup.py` handles this correctly — reuse it rather than
calling `/api/blocklist` directly.

**Fix implemented:** `phase_reconcile_blocklist()`, run every
`--full-sync` pass (no time-gating needed). It fetches the full current
blocklist, and for each entry bumps a repeat-count keyed on
`volume_id:issue_id:link` (not the DB row id, which changes on
re-blocklisting) persisted in `krakoan_setup_state.json`
(`blocklist_repeat_counts`, `blocklist_confirmed_dead`):
- First 1-2 times an entry is seen: **delete** it from the blocklist
  (`DELETE /api/blocklist/<id>`) so the next retry-incomplete pass gives
  it a fresh shot. Cheap and safe — a genuinely dead link just fails
  again and lands back on the blocklist next time it's tried, continuing
  its count.
- 3rd time the same key reappears: treated as a real dead link. Left
  blocklisted for good (stops burning a GetComics request on it every
  run — this is what actually protects against the rate limiter) and
  appended once to `krakoan_dead_links.jsonl` for manual review. Entries
  already in `blocklist_confirmed_dead` are skipped entirely on later
  passes — no re-counting, no duplicate log lines.

Rejected alternative: a blanket periodic full-wipe (`DELETE
/api/blocklist`) on a timer. Tried this first — it does clear false
positives, but it *also* un-blocks genuinely-dead links every cycle,
so they get re-fetched from GetComics forever instead of eventually
being left alone. That's strictly worse for GetComics rate-limit
exposure than the repeat-count approach, not better — directly measured
while validating this bug: a burst of ~600 direct link checks (no
delay) got 429'd by GetComics almost immediately, while the same checks
spaced 1.2s apart didn't. Kapowarr's own sequential `auto_search`
path is already paced for this (see `_wait_for_task_queue_idle` above);
don't add anything — including blocklist handling — that reintroduces
unpaced bursts against GetComics.

### Manually-added files: use `/api/libraryimport`, not `refresh_and_scan`

If you've moved files into a volume's folder yourself (already correctly
named to Kapowarr's convention) and want Kapowarr's own DB to recognize
them as downloaded, don't queue a `refresh_and_scan` task and wait — it
goes through the same single-threaded `TaskHandler` queue as everything
else (see below) and can sit behind 70+ other tasks for a long time.

`GET /api/libraryimport?folder_filter=<path>&limit=<n>` and
`POST /api/libraryimport` (body: `[{"filepath": ..., "id": <comicvine_id>},
...]`) are plain HTTP request handlers, not queued Tasks — same class of
endpoint as `manualsearch` (see the parallelizing-downloads note). GET
proposes ComicVine matches for files, POST confirms them immediately. Used
successfully to instantly register 142 manually-downloaded files as
complete without touching the task queue at all — `issues_downloaded` in
the volume's API response updated the moment the POST returned. This is
also the exact mechanism `kapowarr_batch_import.py` already uses for a
different purpose (initial library import); nothing new to build, just use
it for one-off manual additions too.

### `/api/libraryimport` does its own ComicVine matching — can create a bogus duplicate volume

`GET /api/libraryimport?folder_filter=...` doesn't just propose linking a
file to a volume you already have in mind — it runs its own independent
ComicVine search per file based on the filename, and if the file's title is
generic/ambiguous (e.g. a bare `"X-Men 005 (2020)..."` with no
disambiguating text), it can match to a completely different real
ComicVine volume than you intended. The `POST` confirm step then **creates
a brand-new Kapowarr volume** for that ComicVine ID if one doesn't already
exist — and derives that new volume's folder from the file's actual path,
which can be the *same folder* an existing, correct volume already owns.

Real example: extracted individual issues from an X-Men (2019) bundle
already sitting in Kapowarr's correctly-tracked `X-Men (2019)` volume's
folder, ran `libraryimport` to link them. It silently matched some files
to comicvine_id 2133 ("The X-Men 1963", the original 60-year run) instead
of the intended 2019 volume, and created a whole new Kapowarr volume for
it pointed at the identical folder path — two volumes now claiming the
same directory, a real corruption risk if either tried to reorganize
files. Caught via `docker logs kapowarr` showing `"Adding a volume to the
library: CV ID 2133..."` — not obvious from the API response alone.
Cleaned up with `DELETE /api/volumes/<bad_id>?delete_folder=false` (files
kept, bogus volume record removed).

Don't use `libraryimport`'s fuzzy per-file matching when you already know
the correct target volume (e.g. re-linking extracted bundle contents into
a volume you just downloaded into) — use `refresh_and_scan` instead (a
queued Task, `POST /api/system/tasks {"cmd": "refresh_and_scan",
"volume_id": <id>}`; slower since it's queued, but scoped to that one
volume rather than doing independent ComicVine lookups per file). Reserve
`libraryimport` for genuinely unlinked/unsorted files where you don't
already know the target. After using it, spot-check `docker logs kapowarr`
for unexpected `"Adding a volume to the library"` lines and `GET
/api/volumes` for any new volume sharing a folder with one you already had.

### A GetComics/FlareSolverr stall can hang the whole task queue

Kapowarr processes its task queue one at a time. If a download link needs
FlareSolverr (Cloudflare bypass) and FlareSolverr can't solve the challenge,
Kapowarr's HTTP client retries with backoff (`TOTAL_RETRIES = 5`,
`/app/backend/base/helpers.py`) — each round can take the full 300s
FlareSolverr timeout, so one bad link can block everything queued behind it
for 20+ minutes before it finally gives up and moves on. Observed via
`docker logs kapowarr` showing `Retrying for round N...` at ~5-minute
intervals and `docker logs flaresolverr` showing the same URL failing with
`Timeout after 300.0 seconds` repeatedly. It does eventually resolve itself
(round 5 is the last), it's just slow — check both containers' logs before
assuming a stuck-looking queue needs manual intervention.

Note this is a *separate* failure mode from the volume-level `monitored`
flag issue above — that one produces near-instant, silent 0-result
completions with no log lines at all, which looks completely different from
this slow multi-round retry pattern. Don't misdiagnose one as the other:
"0 results in 0 seconds, repeated across every volume" means check
`volume_data.monitored`; "the queue hasn't moved in minutes" means check
`docker logs kapowarr`/`flaresolverr` for retry rounds.

### Parallelizing downloads: possible, but capped by real per-service rate limits

Kapowarr's `auto_search` Task queue is hard-architecturally single-threaded
(`TaskHandler._process_queue` only ever starts `queue[0]`, no concurrency
setting) — see the queue-hang note above. `GET /api/volumes/<id>/manualsearch`
and `POST /api/issues/<id>/download` are, however, plain HTTP request
handlers, not queued Tasks, and Kapowarr's waitress server runs 10 threads
(`Constants.HOSTING_THREADS`). Verified empirically: two concurrent
`manualsearch` calls both started and finished together (~0.6s each), not
serialized — so driving several volumes' search+download yourself in
parallel via those two endpoints is mechanically possible and does bypass
the queue bottleneck.

`scripts/comics/krakoan_concurrent_download.py` implements this (per
volume: fetch issues, `manualsearch`, pick single-issue `match: true`
candidates, `POST .../download` directly). But real-world concurrency is
capped by genuine external rate limits Kapowarr itself tracks per download
service (`DownloadServiceRateLimitReached`, e.g. Pixeldrain returns a real
HTTP 403 on concurrent hotlinked requests) — 5 concurrent workers tripped
`link_rate_limited` almost immediately, and even 2 workers showed unstable
`no_candidate` results on a second pass shortly after (state from the
rate-limited first attempt seemingly confusing the next `manualsearch`, not
fully root-caused). The script works mechanically but isn't reliable yet —
don't trust it to correctly mark a volume "done" without checking
`triggered`/`failures` counts, and prefer 1-2 workers, not more. The
sequential `krakoan_kapowarr_setup.py --trigger-search` path (slower, but
proven correct) is the safer default until this is debugged further.

### GetComics' own service preference matters

Its indexer settings (`gc_service_preference` on the GetComics indexer) list
which download button Kapowarr prefers when a post offers more than one:
`GetComics` (the site's own direct/mirror link, which routes through a CDN
like `comicfiles.ru` and needs FlareSolverr) vs `MediaFire`, `Pixeldrain`,
`WeTransfer`, `Mega` (plain cloud-storage links, no Cloudflare gate). The
default order puts `GetComics` first. Reordering to try the cloud-storage
mirrors first (`PUT /api/indexers/1` with a reordered
`gc_service_preference` list) measurably cuts how often the FlareSolverr
stall above gets hit — but doesn't eliminate it, since not every post offers
an alternative mirror. There's no setting to shorten or disable the
FlareSolverr retry itself (`TOTAL_RETRIES` is a hardcoded constant, not
exposed via `/api/settings`).
