# SPEC.md — mytools

A small reimplementation of a subset of bedtools. The oracle is **bedtools v2.31.1** as
installed on this VM: if our output differs from it on the same input, we are wrong,
except for the deviations listed in §8.

---

## 1. Scope

**Subcommands in v1:** `sort`, `merge`, `intersect`, `subtract`, `closest`.
*Why:* the subset named in CLAUDE.md, each behaving like bedtools.

**Explicitly NOT in v1:**
- Every other bedtools subcommand.
- Any flag not in the §4 table, in particular: `merge -c/-o`; `intersect -wo/-wao/-loj/-r/-F/-e/-sorted`;
  `subtract -N/-F/-r/-e`; `closest -D/-k/-io/-iu/-id`; `sort -sizeA/-sizeD/-chrThen*/-g/-faidx`;
  opposite-strand `-S` everywhere.
- Index files of any kind (tabix `.tbi`, `.csi`, or our own). *Why:* no memory benefit for
  whole-file operations, no oracle, and would need htslib (see §6). Candidate stretch goal.
- BAM and VCF input.

## 2. Input formats

- **Formats accepted:** BED3 through BED12 (any column count ≥ 3; extra columns carried
  through unchanged), GFF3, and GTF. Format is detected per file, as bedtools does; `-a` and
  `-b` may be different formats.
  *Why:* "all BED formats, GFF3 and GTF".
- **GFF3/GTF coordinates** are 1-based closed. They are converted to 0-based half-open
  internally (`start - 1`) and written back out in their original coordinates, as bedtools
  does. *Why:* match the oracle.
- **Input source:** file argument or stdin. `-` means stdin. At most one input per command
  may be stdin.
- **Compressed input:** gzip accepted, decompressed with `gzip -dc`. Detected from the
  content (gzip magic bytes), not the `.gz` extension, so gzipped stdin works. A golden
  case confirms bedtools behaves the same.
- **Header lines:** lines starting with `#`, `track` or `browser` are skipped. The only
  exception is `-header` (§5), which passes them to the output as bedtools does.

## 3. Interval semantics

- **Coordinate system:** 0-based half-open. `chr1 100 200` covers bases 100..199.
- **Overlap predicate:** same chromosome (and same strand under `-s`), and
  `a.start < b.end && b.start < a.end`. Strict `<`. Defined once, in
  `src/utils/overlap.awk`, and used by every subcommand.
- **Bookended intervals** (`a.end == b.start`) do **not** overlap. They **do** merge under
  `merge` with the default `-d 0`.
- **Zero-length intervals** (`start == end`) are legal. What they overlap is whatever
  bedtools says. Golden tests encode it, with a comment marking it as oracle behaviour.
- **Minimum overlap:** 1 bp by default. `-f <fraction>` (intersect, subtract) requires that
  fraction of the A interval to be covered.

## 4. Flags per subcommand

Every flag has bedtools' name and exact meaning.

| Subcommand  | Flags in v1 | Notes |
|-------------|-------------|-------|
| `sort`      | `-i`, `-header` | Default order only: chromosome (byte order), then start (numeric). |
| `merge`     | `-i`, `-d`, `-s`, `-header` | `-d 0` is the default and merges bookended intervals. |
| `intersect` | `-a`, `-b`, `-wa`, `-wb`, `-u`, `-v`, `-c`, `-f`, `-s`, `-header` | Output keeps A's input order, as bedtools does without `-sorted`. |
| `subtract`  | `-a`, `-b`, `-A`, `-f`, `-s` | Output keeps A's input order. |
| `closest`   | `-a`, `-b`, `-d`, `-s`, `-t` | `-t first\|last\|all`, default `all`. |

- **Strand-aware flags:** `-s` (same strand) only. `-S` is out of v1.
- **Does `merge` need pre-sorted input?** No. It sorts unsorted input itself.
  **Deliberate deviation:** bedtools exits 1 on unsorted input.
- **Does `closest` need pre-sorted input?** No. Same as `merge`, same deviation.
  *Why:* "always sort".

## 5. Output

- **Byte-identical to bedtools** for every v1 flag: tab-separated fields, every line ends
  with `\n`, and an empty result prints nothing and exits 0. *Why:* the golden tests
  compare bytes.
- **`-header`** (`sort`, `merge`, `intersect`): the input's header lines are printed before
  the results, exactly as bedtools prints them.

## 6. Memory model

- **Sort, then stream.**
  1. Sorting uses GNU `sort` (`LC_ALL=C sort -k1,1 -k2,2n`). It holds a bounded buffer and
     spills to temporary files, so RAM does not grow with input size.
  2. Every other subcommand then makes one streaming pass in POSIX `awk`. It holds only the
     intervals that overlap the current position, so memory grows with the densest
     overlapping region, not with file size.
- **Keeping input order:** `intersect` and `subtract` must output in A's original order.
  They tag each A line with its line number, sweep in sorted order, then re-sort by the tag.
  Both sorts are GNU `sort` and use disk, not RAM.
- **Largest input promised:** 100 GB. Revisable.
  - Needs free space in `$TMPDIR` of roughly the input size, uncompressed.
- **Speed:** no absolute target, but nothing quadratic in input size. Slower than bedtools
  is fine.
- **Which commands stream:** after sorting, all five. `sort` itself is an external merge
  sort, bounded in RAM but not single-pass.
- **No files are written except temporary files** in `$TMPDIR`, which are cleaned up on
  exit. No index files, and nothing next to the input (it may be stdin or read-only).

## 7. Errors and exit codes

- **Format:** exit code first, in the GNU `program: file:line: problem` style.
- **Where they go:** always stderr, never stdout.
- **Usage errors** also print the usage line.

| Situation             | stderr message | exit code |
|-----------------------|----------------|-----------|
| Success               | —              | `0` |
| Malformed BED line (fewer than 3 columns, non-integer or negative start/end) | `[1] mytools <cmd>: <file>:<line>: <problem>` | `1` |
| `start > end`         | `[1] mytools <cmd>: <file>:<line>: start (<s>) > end (<e>)` | `1` |
| Unknown flag          | `[2] mytools <cmd>: unknown flag '<flag>'`, then usage | `2` |
| Missing input file    | `[1] mytools <cmd>: <file>: no such file` | `1` |
| Missing required argument (e.g. no `-b`) | `[2] mytools <cmd>: missing <flag>`, then usage | `2` |
| Unknown subcommand, or no arguments | `[2] mytools: ...`, then usage | `2` |
| Unsorted input to `closest` or `merge` | — (sorted internally, §4) | `0` |

## 8. Correctness

- **Oracle:** bedtools v2.31.1 on `data/a.bed`, `data/b.bed`, `data/genes.bed`, plus
  `data/genes.gtf` for GTF input. Non-negotiable.
- **Golden tests in v1:**
  - every subcommand with every flag in §4
  - stdin (`-`)
  - gzipped input, from a file and from stdin
  - `#`, `track` and `browser` header lines, with and without `-header`
  - GTF input
  - For `merge` and `closest`, input is sorted before bedtools sees it. A separate test
    checks that `mytools` gives the same output on unsorted input as on sorted input.
- **Known deviations from bedtools:**
  1. `merge` and `closest` accept unsorted input (bedtools exits 1). *Why:* a product
     decision, "always sort".
  2. Error message text differs. Golden tests compare stdout and exit code, not stderr.
  3. Usage errors exit 2, per CLAUDE.md, even where bedtools uses a different code. The
     golden test says so in a comment wherever this applies.

## 9. Language and layout

- **Implementation language:** bash 5, plus POSIX `awk`, GNU coreutils and `gzip`.
  - No `gawk`-only features: Ubuntu's default `awk` is `mawk`.
  - No htslib and no other dependencies.
  - `LC_ALL=C` everywhere, so sorting and comparisons are by bytes.
- **Layout:** like bedtools, one entry point dispatching to one directory per subcommand,
  with shared code in `utils`:

  ```
  mytools                   entry point: --version, usage, dispatch to src/<cmd>/
  src/utils/common.sh       arg parsing, opening inputs (file, -, gz), header skipping, error()
  src/utils/overlap.awk     the overlap predicate — the only place it is defined
  src/sort/sort.sh
  src/merge/merge.sh        (+ merge.awk)
  src/intersect/intersect.sh
  src/subtract/subtract.sh
  src/closest/closest.sh
  tests/run_golden.sh       golden tests against bedtools
  tests/unit/               unit tests, no bedtools needed
  ```

  Shared `.awk` files are loaded with multiple `-f` flags
  (`awk -f src/utils/overlap.awk -f src/intersect/intersect.awk`), which POSIX allows.
- **Build order:** `src/utils/` is written and merged to `main` **before** the subcommands
  are handed out to parallel agents. It is the only code every subcommand touches.
- **Invocation:** `mytools <subcommand> [flags]`, on `PATH` via a symlink in
  `~/.local/bin`.
