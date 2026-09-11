# CLAUDE.md

Conventions for the `mytools` project. This **overwrites** the `CLAUDE.md` in the repo
root during setup — the one there is notes for the upstream template, not for your
project. It is read automatically at the start of every session, so edit it as your
design firms up, either directly or with the `#` prefix from inside a session.

## My fork — fill this in first

**My fork is `dw-thomson/ai_agent_workshop`.**

Anything that **creates** — `gh issue create`, `gh pr create` — passes
`--repo dw-thomson/ai_agent_workshop`. Never write to
`SACGF/ai_agent_workshop`: that's the shared upstream template and thirty other people
are working from it.

Reading and reviewing someone else's PR is fine when I name their fork explicitly
(`gh pr diff`, `gh pr review --repo <partner>/ai_agent_workshop`). The rule is about
where new things land, not about what you're allowed to look at.

Pass the flag every time. `gh` with a missing or empty `--repo` does not fail — it
silently resolves to the git remote and exits 0, so a forgotten flag looks exactly like
a success.

## What this is

`mytools` is a small reimplementation of a subset of bedtools: `sort`, `merge`,
`intersect`, `subtract`, `closest`. Real `bedtools` (v2.31.1) is installed and is the
oracle — if our output differs from it on the same input, we are wrong.

**`SPEC.md` is the source of truth** for scope, flags, formats, memory model, errors and
layout. Read it before implementing anything. It also lists the only accepted
deviations from bedtools (§8).

## Language

**`mytools` is written in bash**, with POSIX `awk` for the per-line work, plus GNU
coreutils and `gzip`. Every subcommand and every test. Don't introduce a second language
without asking me.

- POSIX `awk` only, no `gawk`-only features. Ubuntu's default `awk` is `mawk`.
- No `while read` loops over data lines, because they're far too slow at 100 GB. Loop in `awk`.
- `LC_ALL=C` everywhere, so sorting and comparisons are by bytes.

One codebase, one language: several agents work on this in parallel and they will each
pick their own otherwise. Reimplementing a single subcommand elsewhere is a deliberate
stretch goal, not a default.

## Interval semantics — read this before touching overlap logic

BED is **0-based, half-open**. `chr1 100 200` covers bases 100..199. Therefore:

- Two intervals overlap iff `a.start < b.end AND b.start < a.end`. Note strict `<`.
- Bookended intervals (`a.end == b.start`) do **not** overlap. They do merge under
  `merge -d 0`.
- Zero-length intervals (`start == end`) are legal in our fixtures and bedtools
  handles them in ways you will not guess. Do not "fix" them — match the oracle.

Every off-by-one bug in this project lives in that comparison. When a golden test
fails, look there first.

## Testing

- `./tests/run_golden.sh` diffs every subcommand against real bedtools on `data/`.
  It does not exist yet — `tests/README.md` has the worked example to build it from.
- **Run it before every commit.** It takes seconds; there is no excuse.
- Fixtures are `data/a.bed`, `data/b.bed` (edge cases), `data/genes.bed`, and
  `data/genes.gtf` for GTF input. Do not regenerate or "tidy" them — the edge cases are
  deliberate.
- `merge` and `closest` golden cases sort the input before bedtools sees it, because
  bedtools exits 1 on unsorted input and we don't (SPEC.md §8).
- New subcommand or flag? Add its golden case in the same commit.
- Unit tests live in `tests/` too and must run without bedtools. One per edge case:
  bookended, zero-length, nested, position 0, and the overlap predicate itself.
- Fixed a failing golden test? Add the unit test that would have caught it first.
- If bedtools does something surprising, the test encodes bedtools' behaviour.
  Add a comment saying why; do not encode what you think it should do.

## Code

- **Sort, then stream.** Sort with GNU `sort`, which spills to disk in `$TMPDIR`. Then
  make one pass in `awk`, holding only the intervals that overlap the current position.
  - Never load a whole file or chromosome into memory. The promise is 100 GB of input.
  - `merge` and `closest` sort their input themselves.
  - `intersect` and `subtract` must still print in A's input order: tag each line with its
    number, sort, then sort back by the tag.
- The overlap predicate lives in `src/utils/overlap.awk` and nowhere else.
- Layout (SPEC.md §9):
  - `mytools` dispatches to `src/<cmd>/`.
  - Shared code is in `src/utils/`, which is written first, before subcommands are built
    in parallel.
  - A subcommand's agent edits only its own `src/<cmd>/`.
- Read from a file argument or stdin (`-` means stdin). Gzipped input is detected from
  its content, not the `.gz` extension.
- Errors go to stderr, never stdout — stdout is data and gets piped. Format:
  `[<code>] mytools <cmd>: <file>:<line>: <problem>`.
- Exit codes:
  - `0` success
  - `1` bad input data, including a missing input file
  - `2` usage error (also print the usage line)
- No third-party runtime dependencies: bash, POSIX `awk`, coreutils, `gzip`. No htslib,
  and no index files.

## Commits and PRs

- Small commits, one logical change each, message referencing the issue: `sort: handle
  unsorted chrom order (#3)`.
- Branch per issue: `feat/3-sort`. Exception: trivial one-liners go straight to main —
  ask me which I want rather than defaulting to a PR.
- Closing an issue means checking the code does what the issue asked, not remembering
  that you wrote it.
- PRs go to **your own fork** — see the fork rule at the top of this file.
