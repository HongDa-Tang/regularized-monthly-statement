# CLAUDE.md

## What this project is

Sample project for [provenance](https://github.com/hongdatang/provenance): demonstrates UC-D (computation tracing) using tjq for Excel-like JSON computation with field-level lineage, queryable via [tracing](https://github.com/hongdatang/tracing). See [README.md](README.md).

## Running

```bash
TJQ=/path/to/tjq ./tjq-fanout --input input --output <output-dir> -f monthly-traced.jq

# Trace a field back to its source
python -m tracing <output-dir> --location '<file>#<json-pointer>'
```

## Layout

- `monthly-traced.jq` — the jq filter (core logic)
- `tjq-fanout` — general-purpose M→N wrapper for tjq; conforms to provenance tool protocol. See README.md § tjq-fanout.
- `input/` — source bank statement JSONs

Generated output directories are gitignored.
