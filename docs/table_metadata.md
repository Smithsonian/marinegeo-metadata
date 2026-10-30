# Table metadata

`table-metadata/` declares what each MarineGEO data table looks like and the QC
rules that apply to it. It is the source of truth for
`marinegeo.utils::qc_run()`, which resolves it at runtime — so adding a rule
needs no code change.

Five directories of flat CSVs, one concern each. Files within a directory share
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
  column-ids/                          # what each column holds: label, unit
    cross_protocol_ids.csv             # ids used by more than one protocol
    darwin-core_column-ids.csv
    fouling-panels_column-ids.csv
    oyster-experiment-2025_column-ids.csv
    oyster-reef-monitoring_column-ids.csv
    reef-life-survey_column-ids.csv
    seagrass-monitoring_column-ids.csv
    sites-and-partners_column-ids.csv
    taxonomy-and-functional-groups_column-ids.csv
  numeric-ranges/                      # numeric bounds, optionally taxon-scoped
    cross_protocol_ranges.csv
    oyster-reef-monitoring_numeric-ranges.csv
    seagrass-monitoring_numeric-ranges.csv
  controlled-vocabularies/             # permitted values
    cross_protocol_vocabularies.csv
    fouling-panels_controlled-vocabularies.csv
    oyster-experiment-2025_controlled-vocabularies.csv
    oyster-reef-monitoring_controlled-vocabularies.csv
    seagrass-monitoring_controlled-vocabularies.csv
  column-lookups/                      # which columns are registry-checked
    cross_protocol_lookups.csv
```

These are the authored files. The flat tables the QC engine consumes are
generated into [`dist/`](../dist/README.md) by `R/generate-metadata-dist.R` —
never edit those.

## How rules are addressed

**All three rule tables key on `column_id`, not on `table_id` + `column_name`.**
A `column_id` names *what a column holds*; `data-structure/` is what binds an
id to a particular column of a particular table. So:

- Two columns that share a name but not a meaning cannot share rules — give
  them different ids.
- Two columns with different names that hold the same thing share one id, and
  one rule row covers both.

## data-structure/

`protocol,table_id,column_name,data_type,missing_values,uuid_identity,column_id`

One row per column of one table.

| Field | Meaning |
|---|---|
| `protocol` | Monitoring or experiment program, e.g. `Seagrass Monitoring`. Also decides which file the row belongs in. |
| `table_id` | The table this column belongs to, e.g. `seagrass-cover-monitoring-v1`. Must appear in `marinegeo_data_index.csv`. |
| `column_name` | Expected column name in the data table. |
| `data_type` | One of `STRING`, `DOUBLE`, `INT`, `TINYINT`, `DATE`, `BOOL`, `BOOLEAN`. |
| `missing_values` | `fail`, `warn` or `allow`. Empty means no missing-value rule. |
| `uuid_identity` | `TRUE` on the columns that together identify a row, otherwise empty. Never `FALSE`. |
| `column_id` | **Required on every row**, and must be defined in `column-ids/`. Several rows naming the same `column_id` is normal and intended — that is how one rule reaches several columns. A blank is a validator FAIL: the column would silently have no rules, no label and no unit, and nothing downstream could tell that from a column that genuinely has none. |

**Row order is significant.** `qc_check_columns()` reports column *order*
problems, and the expected order is the row order of this table — which is the
sorted filename order, then the row order within each file.

## column-ids/

`column_id,label,definition,unit`

One row per unique column ID — 239 ids covering all 570
`database_structure` rows. `column_id` is lower-case `^[a-z0-9_]+$` and unique.
The split
across files is purely for navigation: `cross_protocol_ids.csv` for ids used by
more than one protocol, and one file per protocol for the rest.

| Field | Meaning |
|---|---|
| `column_id` | The identifier the rule tables key on. |
| `label` | Human-readable name, e.g. `Percent cover`. Required. |
| `definition` | Prose definition |
| `unit` | The unit, e.g. `mm`, `degree`. Blank where there is no meaningful one. `unit` lives *only* here — not on `database_structure`. |

### The naming principle

A `column_id` names what a column holds, **including whatever about the sampling
design or coding system determines its valid values.** It is not a
protocol-specific value.

Two ids may share a `label` and `unit`.

## numeric-ranges/

`column_id,scope_type,scope_value,range_type,max_fail,min_fail,max_warn,min_warn`

One row per range rule. `range_type` is `inclusive` or `exclusive` and decides
whether a value exactly on a bound passes. Bounds may be left empty
individually — a rule may warn without failing, or bound one side only.

**`range_type` must never be blank.**

There is no authored `rule_id`:

- **`rule_id` is derived** by `R/generate-metadata-dist.R` and exists only in
  `dist/`. It is `column_id` for an unconditional rule and
  `column_id__<scope_type>__<scope_value>` for a scoped
  one, e.g. `leaf_length_mm__taxon_within__genus_zostera`.

The uniqueness key is `(column_id, scope_type, scope_value)`, deliberately
excluding `range_type`: two rows differing only in `range_type` is invalid.
Because `rule_id` derives from exactly that tuple, it is unique by construction.

### Scoping a range to a clade or functional group

Rather than enumerate species, a rule can name a clade or a functional group
and let the registry supply the members. A Zostera leaf is 20–1200 mm and a
Halodule leaf is not, so:

```
column_id,scope_type,scope_value,range_type,max_fail,min_fail,max_warn,min_warn
leaf_length_mm,taxon_within,Genus:Zostera,inclusive,,,1200,20
```

| `scope_type` | `scope_value` | the rule applies when |
|---|---|---|
| `taxon_within` | `Rank:Name` (`Genus:Zostera`, `Family:Zosteraceae`) or a full LSID (`urn:lsid:marinespecies.org:taxname:495077`) | the row's taxon is at or below that node of `taxonomic_lookup` |
| `taxon_not_within` | same | it is not |
| `in_functional_group` | `tree:Label` (`vegetation:Marine Seagrass`) | the row's taxon is at or below that node of a `functional_group_lookup` tree |
| `not_in_functional_group` | same | it is not |

Blank `scope_type` *and* blank `scope_value` is an unconditional rule. Setting
one without the other is a validator FAIL — a `scope_type` with no value is a
rule the engine refuses to apply, and a value with no type is a restriction its
author believes is in force and that nothing enforces.

Things to know:

- **The `tree:` prefix is required** for functional groups. 540 of the 1,575
  node labels occur in more than one tree (`Algae` is in both
  `oyster_composition` and `vegetation`), so a bare label warns and the rule is
  not applied. The trees are `fouling`, `oyster_composition`, `oyster_density`
  and `vegetation`.
- **A node counts as its own ancestor**, so `Species:Zostera marina` matches
  exactly that species.
- **`|` is a union, and it is the only OR.**
  `taxon_within` / `Genus:Zostera|Genus:Halodule` means either genus.
- **Ranks are normalised**, so `Phylum:Tracheophyta` matches rows stored as
  `"Phylum (Division)"`.
- **An unconditional rule and a scoped rule on the same `column_id` both
  apply.** The scope narrows *that* rule, it does not override the other one. A
  value can therefore raise two issues, told apart by `rule_id`.

## controlled-vocabularies/

`column_id,value`

One row per permitted value. Values are always read as text, so `0.1` and `TRUE` stay
strings and are compared as written.

Because this table keys on `column_id`, two
columns sharing an id share one vocabulary. If two tables use the same column
name but do *not* permit the same values, they need different `column_id`s — or
re-keying silently widens the vocabulary and the check passes on values it
should reject.

## column-lookups/

`column_id,registry_table,registry_column`

Which columns are validated against a registry, and against what. Four rows:

```
column_id,registry_table,registry_column
partner_code,partner_codes,partner_code
scientific_name,observation_lookup,scientific_name
site_code_marinegeo,site_codes,site_code
site_name_marinegeo,site_codes,site_name
```

## CSV conventions

- **UTF-8, no BOM.** A BOM corrupts the first column name of whichever file
  sorts first in its directory, which silently removes that column. The
  generator refuses to build if a rule-table CSV has one.
- **LF line endings** (enforced by `.gitattributes`), with a trailing newline.
- **Empty cell for "not set"** — never `NA`, `NULL` or `~`.
- Within a directory every file must carry exactly the header above, in that
  order. An extra, renamed or reordered column means the QC engine reads the
  whole table as having no rules, which surfaces as a clean QC pass rather than
  an error.

## Changing something

1. Edit the CSV. A new `column_id` needs a `column-ids/` row **and** a
   `data-structure/` row pointing at it before any rule can use it.
2. `Rscript R/generate-metadata-dist.R` — rebuilds `dist/`.
3. `Rscript R/validate.R` — checks the headers, the enums, that every
   `column_id` is defined and reachable from `database_structure`, that columns
   sharing an id agree on `data_type`, that scope references parse, and that the
   row order still matches `dist/`. It also prints each id's *reach* — how many
   columns in how many tables it now covers — because nothing can mechanically
   detect an id applied to three of the five columns that should share it. Read
   that list when you add or re-point an id.
4. Commit the CSV **and** the regenerated `dist/`.

