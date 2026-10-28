# Table metadata

`table-metadata/` declares what each MarineGEO data table looks like and the QC
rules that apply to it. It is the source of truth for
`marinegeo.utils::qc_run()`, which resolves it at runtime — so adding a rule
needs no code change.

Three directories of flat CSVs, one concern each. Files within a directory share
a header and are row-bound in sorted filename order, so a protocol's rules live
in whichever file its name routes to.

```
table-metadata/
  data-structure/                      # columns, types, required-ness
    darwin-core_data-structure.csv
    fouling-panels_data-structure.csv
    marinegeo_metadata_tables.csv      # the registry lookups' own structure
    oyster-experiment-2025_data-structure.csv
    oyster-reef-monitoring_data-structure.csv
    reef-life-survey_data-structure.csv
    seagrass-monitoring_data-structure.csv
  categorical-values/                  # controlled vocabularies
    fouling_monitoring_vocab.csv
    oyster_monitoring_and_experiments_vocab.csv
    seagrass_monitoring_vocab.csv
  numeric-ranges/                      # numeric bounds
    oyster_monitoring_numeric_ranges.csv
    seagrass_monitoring_numeric_ranges.csv
```

These are the authored files. The flat tables the QC engine consumes are
generated into [`dist/`](../dist/README.md) by `R/generate-metadata-dist.R` —
never edit those.

## data-structure/

`protocol,table_id,column_name,data_type,missing_values,uuid_identity`

One row per column of one table.

| Field | Meaning |
|---|---|
| `protocol` | Monitoring or experiment program, e.g. `Seagrass Monitoring`. Also decides which file the row belongs in. |
| `table_id` | The table this column belongs to, e.g. `seagrass-cover-monitoring-v1`. Must appear in `marinegeo_data_index.csv`. |
| `column_name` | Expected column name in the data table. |
| `data_type` | One of `STRING`, `DOUBLE`, `INT`, `TINYINT`, `DATE`, `BOOL`, `BOOLEAN`. |
| `missing_values` | `fail`, `warn` or `allow`. Empty means no missing-value rule. |
| `uuid_identity` | `TRUE` on the columns that together identify a row, otherwise empty. Never `FALSE`. |

**Row order is significant.** `qc_check_columns()` reports column *order*
problems, and the expected order is the row order of this table — which is the
sorted filename order, then the row order within each file. Moving a row changes
what the QC engine expects, so keep a table's columns together and in the order
the data has them.

## categorical-values/

`table_id,column_name,value`

One row per permitted value. A column with no rows here is unconstrained.
Values are always read as text, so `0.1` and `TRUE` stay strings and are
compared as written.

## numeric-ranges/

`table_id,column_name,range_type,max_fail,min_fail,max_warn,min_warn`

One row per range rule. `range_type` is `inclusive` or `exclusive` and decides
whether a value exactly on a bound passes. Bounds may be left empty
individually — a rule may warn without failing, or bound one side only.

**`range_type` must never be blank on a row that sets a bound.** The QC engine
drops rows with no `range_type`, so such a rule looks live to whoever wrote it
and does not exist to the engine. A row with no `range_type` *and* no bounds is
a deliberate placeholder for a range nobody has decided yet, and is ignored.

## CSV conventions

- **UTF-8, no BOM.** A BOM corrupts the first column name of whichever file
  sorts first in its directory, which silently removes that column. The
  generator refuses to build if a rule-table CSV has one.
- **LF line endings** (enforced by `.gitattributes`), with a trailing newline.
- **Empty cell for "not set"** — never `NA`, `NULL` or `~`.
- Within a directory every file must carry exactly the header above. An extra or
  renamed column means the QC engine reads the whole table as having no rules,
  which surfaces as a clean QC pass rather than an error.

## Changing something

1. Edit the CSV.
2. `Rscript R/generate-metadata-dist.R` — rebuilds `dist/`.
3. `Rscript R/validate.R` — checks the headers, the enums, that every rule keys
   to a column that exists, and that the row order still matches `dist/`.
4. Commit the CSV **and** the regenerated `dist/`. There is no CI, so step 3 is
   the only thing that catches an authoring mistake before it reaches users.
