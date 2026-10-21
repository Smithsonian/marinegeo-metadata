# Table metadata

`table-metadata/` declares what each MarineGEO data table looks like and the QC
rules that apply to it. It is the source of truth for
`marinegeo.utils::qc_run()`, which resolves it at runtime — so adding a rule
needs no code change.

One YAML file per protocol. Each file declares its tables, each table its
columns in order, and each column the rules that constrain it.

```
table-metadata/
  darwin-core.yaml
  fouling-panels.yaml
  marinegeo-metadata-tables.yaml     # the registry lookups' own structure
  oyster-experiment-2025.yaml
  oyster-reef-monitoring.yaml
  reef-life-survey.yaml
  seagrass-monitoring.yaml
```

These are the authored files. The flat tables the QC engine consumes are
generated into [`dist/`](../dist/README.md) by `R/generate-metadata-dist.R` —
never edit those.

## Shape

```yaml
schema_version: 1
protocol: Seagrass Monitoring     # file-level default
level: 2                          # file-level default

tables:
- table_id: seagrass-leaf-monitoring-v1
  columns:
  - name: sample_event_id
    type: STRING
    missing: enforce
    uuid_identity: true
  - name: leaf_length_mm
    type: DOUBLE
    missing: warn
    numeric_range:
    - range_type: exclusive
      min_fail: 0
    - range_type: inclusive
      min_warn: 20
      max_warn: 1200
      when:
        label: zostera_leaves
        description: Leaf of a Zostera species
        all:
        - column: scientific_name
          taxon_within: Genus:Zostera
```

`protocol` and `level` may be overridden on an individual table.

**`columns:` is a sequence, not a mapping.** Column order is significant —
`qc_check_columns()` reports a column-order issue against it — and a YAML
mapping is unordered. A sequence also lets a column be named `137.5` or `n`,
which as mapping keys would be mangled by YAML's type resolution.

### Column fields

| Field | Meaning |
|---|---|
| `name` | Column name. Quote it if it looks numeric: `- name: "137.5"` |
| `type` | `STRING`, `INT`, `TINYINT`, `DOUBLE`, `DATE`, `BOOL` |
| `missing` | `enforce`, `warn`, or `allow`. Omit for no rule |
| `uuid_identity` | `true` when the column is part of the row identity |
| `one_of` | Controlled vocabulary |
| `numeric_range` | One range mapping, or a sequence of them |

### Controlled vocabularies

```yaml
  - name: cover_method
    type: STRING
    one_of: [Braun-Blanquet, point count, percent bins]

  - name: cover_code
    type: DOUBLE
    one_of: ["0", "0.1", "0.5", "1"]     # quoted: these are strings
```

### Numeric ranges

`range_type` is required and discriminates the entry: `inclusive`, `exclusive`,
or `~` (none). Bounds are `max_fail`, `min_fail`, `max_warn`, `min_warn`; omit
the ones that do not apply.

A `range_type: ~` entry declares no bounds. Note that bounds given *alongside*
`range_type: ~` are ignored by the QC engine — if you write bounds, give the
entry a real `range_type`.

### Table-scoped checks

Rules spanning several columns hang off the table, not a column.

```yaml
  checks:
    aggregate:
    - rule_id: seagrass_cover_point_total
      group_by: [sample_event_id, transect, quadrat]
      value: point_count
      function: sum
      comparison: "=="            # quoted
      target_column: points_in_quadrat
      severity: fail
      description: Point counts in a quadrat must sum to points_in_quadrat

    cross_table:
    - rule_id: leaf_quadrat_in_cover
      relation: subset
      right_table: seagrass-cover-monitoring-v1
      group_by: [sample_event_id, transect]
      on:
      - left: quadrat
        right: quadrat
      severity: fail
```

An aggregate rule takes **either** `target_column` **or** `target_value`
(optionally with `tolerance`), never both.

A cross-table rule is hosted on the **left** table — the one whose rows are
checked, and against which failures are reported. `on:` pairs the join columns
by name, so a left/right length mismatch is not expressible.

### Predicates (`when:`)

A rule applies conditionally when it carries a `when:` block:

```yaml
      when:
        label: primary_points            # optional; pins the reported id
        description: Excluding canopy taxa from the point total
        all:
        - column: cover_type
          not_in: [canopy taxa]
```

`all:` is the only combinator — terms are AND-ed. **There is no `any:`**; the
QC engine composes predicates with `&` only, so an `any:` block is rejected
outright rather than silently misread. Express a disjunction as a multi-value
`in:`.

Each term names one `column` and exactly one operator:

`in`, `not_in`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `is_na`, `not_na`, `matches`,
`taxon_within`, `taxon_not_within`, `in_functional_group`,
`not_in_functional_group`

The set is **closed on purpose**. This metadata is fetched over the network into
every user's session, so an operator that evaluated code would make this repo a
remote code-execution path. Adding one is a deliberate edit in
`marinegeo.utils` (`R/qc_mg_conditional.R`), not something metadata can do.

`is_na` / `not_na` take no operand; write `not_na: true`.

Predicates are written inline where they are used, so there are no condition
ids to keep in sync. `label:` is optional and only pins the id that appears in
QC messages. A predicate genuinely shared by several rules can go in a
file-level `conditions:` block.

## Quoting

`yaml::as.yaml` quotes correctly when generating, but hand-edits need care.
YAML 1.1 resolves unquoted scalars aggressively — `0.1` becomes a number, and
`y`, `N`, `no`, `on`, `yes`, `off` all become booleans. Quote:

- column names that look numeric — `- name: "137.5"`
- vocabulary values that look numeric or boolean — `["0", "0.1", "TRUE"]`
- comparison operators — `">="` (bare `>` is a YAML block indicator and will
  not parse)

Source files must be **valid UTF-8**.

## Changing something

1. Edit the protocol YAML.
2. `Rscript R/generate-metadata-dist.R` — this validates the schema and all
   cross-references, and refuses to write if anything fails.
3. `Rscript R/validate.R` — runs the registry tables against their own QC rules.
4. Commit the YAML **and** the regenerated `dist/`. CI fails if they disagree.