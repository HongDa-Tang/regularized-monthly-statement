# regularized-monthly-statement

Sample project demonstrating how [tjq](https://github.com/hongdatang/tjq) enables Excel-like computation on JSON data with full field-level lineage — a building block of the [provenance](https://github.com/hongdatang/provenance) system's spreadsheet-replacement vision.

## Context

The [provenance](https://github.com/hongdatang/provenance) project aims to replace spreadsheet-based audits with a pipeline of tools, where every derived value is traceable back to its source — just as every spreadsheet cell exposes its formula. The [evtrace](https://github.com/hongdatang/evtrace) library provides the generic lineage query engine, answering *"where did this specific value come from?"* for any tool that emits a `lineage.json`.

This project is a concrete sample of **UC-D (computation tracing)** from that system: a jq filter that reads multiple input files, performs Excel-like reshuffling and aggregation (pooling transactions across overlapping date ranges, recomputing totals), and produces multiple output files — with tjq recording the lineage of every output field automatically.

### Where this fits in the provenance pipeline

```
PDF → hybrid-ocr → .txt → LLM extraction → {month}-ish-statement.json
                                                      │
                                          ┌───────────┘
                                          ▼
                              ╔═══════════════════════════╗
                              ║  this project (UC-D)      ║
                              ║  tjq + monthly-traced.jq  ║
                              ╚═══════════════════════════╝
                                          │
                                          ▼
                                  {YYYY-MM}.json  (calendar-month statements)
                                          │
                                          ▼
                              sum_debits / sum_credits / reconcile (UC-D)
                                          │
                                          ▼
                                    annual.json
```

Each node is independently traceable via its own `lineage.json`. The evtrace library stitches them into one walkable graph at query time.

## The computation

Bank statements span arbitrary date ranges (e.g., Dec 20 – Jan 23, Jan 24 – Feb 21). This jq filter transforms them into clean calendar-month statements:

1. Pool all transactions and daily balances from all input files.
2. Deduplicate and sort by date.
3. Derive the set of calendar months present in the data.
4. For each month, emit a complete statement with the correct transactions, daily balances, opening/closing balances, and deposit/withdrawal totals.

This is the kind of work that would traditionally live in a spreadsheet — grouping rows by month, summing columns, carrying balances forward. tjq makes it traceable: every output field records which input field it came from and what jq expression produced it.

## Tracing the output

After running the pipeline, every field in every output file can be traced back to its source using the [evtrace](https://github.com/hongdatang/evtrace) CLI:

```bash
# Generate output with lineage
TJQ=/path/to/tjq ./tjq-fanout --input input --output tjq-fanout-output -f monthly-traced.jq

# Query: where did this amount come from?
python -m evtrace tjq-fanout-output \
  --location '2025-01.json#/statements/0/transactions/0/amount'
```

```
Trace for 2025-01.json#/statements/0/transactions/0/amount  (tjq-fanout)
Query → final value: -1750.0

 ● jq                     created            content=-1750.0
                            evidence: computation [computation]
                                      function=statements/0/transactions/10/amount
                                      inputs (fan-in):
                                        jan-ish-statement.json#/statements/0/transactions/10/amount = -1750.0
```

The trace shows that the output value `-1750.0` at `2025-01.json` transaction index 0 came from `jan-ish-statement.json` transaction index 10 — the index shifted because the jq filter partitioned the input's Dec–Jan transactions into separate calendar months.

### What the lineage captures

Each entry in `artifacts/lineage.json` records:

- **output_path** — JSON Pointer to the output field (e.g., `/statements/0/transactions/0/amount`)
- **inputs** — source file, JSON Pointer, and value at compute time
- **function** — the jq expression that produced the value

The output directory also contains a `.evtrace` descriptor file, which the evtrace CLI reads to discover the pipeline configuration without needing a `--pipeline` flag.

## Usage

```bash
TJQ=/path/to/tjq ./tjq-fanout --input input --output <output-dir> -f monthly-traced.jq
```

- `TJQ` — path to the [tjq](https://github.com/hongdatang/tjq) binary (defaults to `tjq` on `$PATH`).
- `--input` — directory of source statement JSON files.
- `--output` — directory for per-month output files (created if missing).
- `-f` — the jq filter to run.

## Files

| File | Purpose |
|---|---|
| `monthly-traced.jq` | jq filter: pools inputs, partitions by calendar month, emits `{filename, filedata}` per month |
| `tjq-fanout` | General-purpose M-input → N-output wrapper for tjq; conforms to evtrace tool protocol |
| `input/` | Source bank statements (irregular date ranges) |

## tjq-fanout

A general-purpose wrapper that bridges tjq (which writes a single output stream) to the evtrace tool protocol (`--input <dir> --output <dir>`).

**Contract:** the jq filter must emit one JSON object per output file:

```json
{"filename": "<name>", "filedata": <json>}
```

**What it does:**

1. Runs tjq with `--trace-dir` to capture lineage, producing `{filename, filedata}` objects.
2. Splits each object into `$output_dir/$filename` containing only `.filedata`.
3. Rewrites lineage: groups entries by output index, discards `/filename` entries, strips the `/filedata` prefix, computes per-file SHA-256 hashes.
4. Writes `artifacts/lineage.json` and `.evtrace` in the output directory.

## Input/output format

Both use the same bank-statement schema (`schema_version: "1.0.0"`):

```
{schema_version, institution, account, statements: [{
  period: {start, end},
  balances: {opening, closing, ...},
  daily_balances: [{date, balance}],
  transactions: [{id, posted_date, amount, description, ...}]
}]}
```

Input files have irregular periods spanning parts of two months. Output files are scoped to a single calendar month (`YYYY-MM-01` to `YYYY-MM-{last_day}`, id `stmt_YYYY-MM`).
