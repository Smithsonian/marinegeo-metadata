# Validate this repo's metadata against its own QC rules.
#
# Run from the repo root:
#   Rscript R/validate.R
#
# Exits non-zero on any failure
#
# Checked in order:
#   1.  dist/ is current with respect to the authored sources.
#   2.  The authored rule-table CSVs are well formed and cross-referentially
#       complete on `column_id`, the key all three rule tables hang off.
#   2b. Every scope reference -- range and lookup -- resolves against the live
#       registry.
#   3.  The registry lookup tables pass the QC rules they themselves declare.
#   4.  Functional group assignment.
#   5.  A scoped range rule fires end to end, on the row it should and no other.

library(readr, quietly = TRUE, warn.conflicts = FALSE)
library(dplyr, quietly = TRUE, warn.conflicts = FALSE)

root <- normalizePath(".", mustWork = TRUE)
failures <- character(0)

# The authored source list, the rule-table headers and their declared column
# types, shared with R/generate-metadata-dist.R.
source(file.path(root, "R", "sources.R"))

fail <- function(...) {
  msg <- paste0(...)
  failures <<- c(failures, msg)
  message("FAIL: ", msg)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# marinegeo.utils, new enough to read dist/
# ---------------------------------------------------------------------------

# An installed build from before the rule tables were cut back still has the
# schema-version symbols, so probing for those alone accepts a package that then
# reports every registry table as missing a column that no longer exists.
#
# Symbol existence is not enough on its own either: every build since the dist/
# rewrite has `.mg_registry_required_cols`, so what distinguishes a build that
# understands the column_id schema is its CONTENT. Both probes are needed --
# without the content check this script silently validated against an installed
# package and reported `numeric_ranges` as missing `table_id`, a column the
# authored table has not had since the re-key.
.needed <- c(
  ".mg_dist_schema_version",
  ".mg_dist_schema_version_min",
  ".mg_registry_required_cols",
  ".qc_lookup_scope_types",
  "utl_mg_expand_taxon_set"
)
.needed_tables <- c("column_ids", "column_lookups")
.has_new_api <- function() {
  ns <- tryCatch(asNamespace("marinegeo.utils"), error = function(e) NULL)
  if (is.null(ns)) {
    return(FALSE)
  }
  if (!all(vapply(.needed, exists, logical(1), envir = ns, inherits = FALSE))) {
    return(FALSE)
  }
  all(.needed_tables %in% names(get(".mg_registry_required_cols", envir = ns)))
}

if (!(requireNamespace("marinegeo.utils", quietly = TRUE) && .has_new_api())) {
  pkg <- Sys.getenv(
    "MARINEGEO_UTILS_PATH",
    file.path(dirname(root), "marinegeo-R-utilities")
  )
  if (!dir.exists(pkg)) {
    stop(
      "marinegeo.utils with dist/ support is required ",
      "(install it, or set MARINEGEO_UTILS_PATH)"
    )
  }
  message("using marinegeo.utils from ", pkg)
  suppressMessages(pkgload::load_all(pkg, quiet = TRUE))
}
ns <- asNamespace("marinegeo.utils")

# Sections 2-4 below read the published bundles through this package. A package
# that cannot read the schema we publish would report "no rules" rather than an
# error, so the run would pass having checked nothing.
.dist_schema <- jsonlite::fromJSON(
  file.path(root, "dist", "manifest.json"),
  simplifyVector = FALSE
)$schema_version
if (
  !is.null(.dist_schema) &&
    (get(".mg_dist_schema_version_min", envir = ns) > .dist_schema ||
      get(".mg_dist_schema_version", envir = ns) < .dist_schema)
) {
  stop(
    "the marinegeo.utils in use reads dist schema ",
    get(".mg_dist_schema_version_min", envir = ns),
    "-",
    get(".mg_dist_schema_version", envir = ns),
    " but dist/ publishes ",
    .dist_schema,
    ". Install the current marinegeo.utils, or point MARINEGEO_UTILS_PATH at ",
    "a checkout that has it."
  )
}

# Resolve registries from THIS working tree, not from the remote default
# branch -- otherwise an unmerged change validates against main and the run is
# meaningless. Strict mode turns a resolution failure into an error rather than
# a silent fall back to the in-package copy, which here would validate the wrong
# rules entirely.
options(
  marinegeo.utils.metadata_local = root,
  marinegeo.utils.strict_registry = TRUE
)

# ---------------------------------------------------------------------------
# 1. Is dist/ current?
# ---------------------------------------------------------------------------

message("\n== dist/ freshness ==")

manifest_path <- file.path(root, "dist", "manifest.json")
if (!file.exists(manifest_path)) {
  fail("dist/manifest.json is missing. Run: Rscript R/generate-metadata-dist.R")
} else {
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
  recorded <- manifest$sources

  current <- mg_source_files(root)
  rel <- sub(paste0("^", root, "/"), "", current)

  added <- setdiff(rel, names(recorded))
  removed <- setdiff(names(recorded), rel)
  changed <- vapply(
    intersect(rel, names(recorded)),
    function(r) {
      !identical(
        digest::digest(file = file.path(root, r), algo = "sha256"),
        as.character(recorded[[r]])
      )
    },
    logical(1)
  )
  changed <- names(changed)[changed]

  if (length(added) || length(removed) || length(changed)) {
    for (f in added) {
      message("  + ", f, " (not in manifest)")
    }
    for (f in removed) {
      message("  - ", f, " (in manifest, not on disk)")
    }
    for (f in changed) {
      message("  ~ ", f, " (changed since dist/ was built)")
    }
    fail(
      "dist/ is stale. Run: Rscript R/generate-metadata-dist.R"
    )
  } else {
    message("  dist/ matches all ", length(rel), " source files")
  }
}

# ---------------------------------------------------------------------------
# 2. Are the authored rule tables well formed?
# ---------------------------------------------------------------------------
#
# Every check here exists because of one failure mode: a rule table that cannot
# be read, or a rule that cannot match anything, is reported downstream as "no
# rules to apply" -- a clean QC pass that checked nothing. An authoring mistake
# therefore has to fail HERE, loudly, or it never fails at all.
#
# Checks are accumulated with fail() rather than stop() so one run reports every
# problem.

message("\n== table-metadata rule tables ==")

data_types <- c("STRING", "DOUBLE", "INT", "TINYINT", "DATE", "BOOL", "BOOLEAN")
missing_values_enum <- c("fail", "warn", "allow")
range_types <- c("inclusive", "exclusive")

# The registry tables describe their own structure and are not data products, so
# they are the one legitimate absence from the data index.
registry_table_ids <- c(
  "observation_lookup",
  "taxonomic_lookup",
  "nested_labelsets",
  "site_lookup",
  "partner_lookup",
  # Darwin Core / OBIS exchange formats: published structures rather than
  # MarineGEO data products, so they are not in the data index either.
  "event_darwin_core_obis",
  "occurrence_darwin_core_obis",
  "emof_darwin_core_obis"
)

# Per-file, on the raw bytes, before anything is parsed.
for (f in sort(list.files(
  file.path(root, "table-metadata"),
  pattern = "\\.csv$",
  recursive = TRUE,
  full.names = TRUE
))) {
  rel_f <- sub(paste0("^", root, "/"), "", f)
  raw <- readBin(f, "raw", file.size(f))
  if (length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) {
    fail(
      rel_f,
      ": starts with a UTF-8 BOM, which corrupts the first column name"
    )
  }
  if (any(raw == as.raw(13))) {
    fail(rel_f, ": has CRLF line endings; this repo is LF (see .gitattributes)")
  }
  if (length(raw) > 0 && raw[length(raw)] != as.raw(10)) {
    fail(rel_f, ": has no trailing newline")
  }
  lines <- length(readLines(f, warn = FALSE))
  if (lines < 2L) {
    fail(
      rel_f,
      ": has a header but no rows; an empty rule file reads as 'no rules'"
    )
  }
}

rules <- list()
for (tn in names(mg_rule_tables)) {
  spec <- mg_rule_tables[[tn]]
  files <- sort(list.files(
    file.path(root, spec$dir),
    pattern = "\\.csv$",
    full.names = TRUE
  ))
  if (length(files) == 0L) {
    fail(spec$dir, ": no CSVs")
    next
  }
  # Read exactly the way the generator does, so this validates what gets
  # published rather than an approximation of it.
  tbl <- tryCatch(
    readr::read_csv(
      files,
      col_types = mg_rule_col_types[[tn]],
      progress = FALSE
    ),
    error = function(e) {
      fail(spec$dir, ": error reading CSV - ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(tbl)) {
    next
  }
  if (!identical(colnames(tbl), spec$cols)) {
    fail(
      spec$dir,
      ": columns are ",
      paste(colnames(tbl), collapse = ", "),
      " but must be exactly ",
      paste(spec$cols, collapse = ", ")
    )
    next
  }
  if (nrow(tbl) == 0L) {
    fail(spec$dir, ": no rows")
    next
  }
  rules[[tn]] <- tbl
  message("  ", spec$dir, ": ", nrow(tbl), " rows, header ok")
}

ds <- rules$database_structure
if (!is.null(ds)) {
  if (any(is.na(ds$table_id) | is.na(ds$column_name))) {
    fail("database_structure: NA table_id or column_name")
  }
  bad_type <- setdiff(stats::na.omit(unique(ds$data_type)), data_types)
  if (length(bad_type) > 0) {
    fail(
      "database_structure: unknown data_type(s): ",
      paste(bad_type, collapse = ", ")
    )
  }
  bad_mv <- setdiff(
    stats::na.omit(unique(ds$missing_values)),
    missing_values_enum
  )
  if (length(bad_mv) > 0) {
    fail(
      "database_structure: unknown missing_values(s): ",
      paste(bad_mv, collapse = ", "),
      " (allowed: ",
      paste(missing_values_enum, collapse = ", "),
      ")"
    )
  }
  if (any(!is.na(ds$uuid_identity) & !ds$uuid_identity)) {
    fail("database_structure: uuid_identity must be TRUE or empty, never FALSE")
  }
  dup <- unique(paste(ds$table_id, ds$column_name)[
    duplicated(paste(ds$table_id, ds$column_name))
  ])
  if (length(dup) > 0) {
    fail(
      "database_structure: duplicate (table_id, column_name): ",
      paste(dup, collapse = "; ")
    )
  }
  # A table absent from the data index is invisible to utl_mg_list_tables() and
  # to the wrangler, so the two must not drift.
  index_path <- file.path(root, "marinegeo_data_index.csv")
  if (file.exists(index_path)) {
    indexed <- readr::read_csv(
      index_path,
      show_col_types = FALSE,
      progress = FALSE
    )$table_id
    orphan_tables <- setdiff(
      unique(ds$table_id),
      c(indexed, registry_table_ids)
    )
    if (length(orphan_tables) > 0) {
      fail(
        "database_structure: table_id(s) absent from marinegeo_data_index.csv: ",
        paste(orphan_tables, collapse = ", ")
      )
    }
  }
}

ci <- rules$column_ids
nr <- rules$numeric_ranges
cv <- rules$controlled_vocabularies
cl <- rules$column_lookups

blank <- function(x) is.na(x) | !nzchar(trimws(x))

# Label a numeric_ranges row the way the published table will, so a message
# names the same id the QC engine reports in `issues$rule_id`.
nr_id <- if (is.null(nr)) character(0) else mg_derive_rule_id(nr)

# --- the column_id key itself ----------------------------------------------

# V14. The id is used as a join key and as part of a derived rule_id, so the
# character set is closed rather than conventional.
if (!is.null(ci)) {
  bad_id <- blank(ci$column_id) | !grepl("^[a-z0-9_]+$", ci$column_id)
  if (any(bad_id)) {
    fail(
      "column_ids: ",
      sum(bad_id),
      " column_id(s) are blank or outside ^[a-z0-9_]+$: ",
      paste(unique(ci$column_id[bad_id]), collapse = ", ")
    )
  }
  dup <- unique(ci$column_id[duplicated(ci$column_id)])
  if (length(dup) > 0) {
    fail("column_ids: duplicate column_id: ", paste(dup, collapse = ", "))
  }
}

# V1. Every database_structure row must name a column_id. A blank one is the
# migration's one unrecoverable gap: the column silently has no rules, no unit
# and no label, and nothing downstream can tell that from a column that
# legitimately has none. `definition` is deliberately NOT checked -- it is
# authored later and is blank on every row today.
if (!is.null(ds)) {
  no_id <- blank(ds$column_id)
  if (any(no_id)) {
    fail(
      "database_structure: ",
      sum(no_id),
      " row(s) with a blank column_id: ",
      paste0(ds$table_id[no_id], ".", ds$column_name[no_id], collapse = ", ")
    )
  }
}

# V15 / V15b. `label` and `unit` are what an export reads, so a blank label is
# a gap. Two ids may share a label by design (two percent covers both export as
# "Percent cover"), but then they must agree on whether there IS a unit --
# disagreeing on presence is an omission, while disagreeing on a non-blank unit
# is a real difference (chain_length_m vs chain_length_cm).
if (!is.null(ci)) {
  no_label <- blank(ci$label)
  if (any(no_label)) {
    fail(
      "column_ids: ",
      sum(no_label),
      " row(s) with a blank label: ",
      paste(ci$column_id[no_label], collapse = ", ")
    )
  }
  for (lbl in unique(ci$label[!no_label])) {
    rows <- ci[!is.na(ci$label) & ci$label == lbl, , drop = FALSE]
    if (nrow(rows) < 2L) {
      next
    }
    units <- unique(ifelse(blank(rows$unit), "", trimws(rows$unit)))
    if (length(units) < 2L) {
      next
    }
    if ("" %in% units) {
      fail(
        "column_ids: label '",
        lbl,
        "' has a unit on some rows and none on others: ",
        paste0(
          rows$column_id,
          " = '",
          ifelse(blank(rows$unit), "", rows$unit),
          "'",
          collapse = ", "
        ),
        " -- one of them is missing its unit"
      )
    } else {
      message(
        "  column_ids: label '",
        lbl,
        "' spans units ",
        paste(units, collapse = ", "),
        " (",
        paste(rows$column_id, collapse = ", "),
        ")"
      )
    }
  }
}

# --- referential integrity, both directions --------------------------------
#
# Every check below exists because a broken column_id reference produces
# silence, not an error: a rule keyed to an id no column carries simply never
# matches a row, and a column whose id is in no rule table simply has no rules.

rule_ids <- function() {
  out <- list()
  for (tn in c("numeric_ranges", "controlled_vocabularies", "column_lookups")) {
    tbl <- rules[[tn]]
    if (!is.null(tbl)) {
      out[[tn]] <- tbl$column_id
    }
  }
  out
}

# V2. A column pointing at an id that does not exist.
if (!is.null(ds) && !is.null(ci)) {
  unknown <- setdiff(unique(ds$column_id[!blank(ds$column_id)]), ci$column_id)
  if (length(unknown) > 0) {
    fail(
      "database_structure: column_id(s) not defined in column-ids/: ",
      paste(sort(unknown), collapse = ", ")
    )
  }
}

# V3. A rule pointing at an id that does not exist.
if (!is.null(ci)) {
  for (tn in names(rule_ids())) {
    unknown <- setdiff(unique(rule_ids()[[tn]]), ci$column_id)
    if (length(unknown) > 0) {
      fail(
        tn,
        ": column_id(s) not defined in column-ids/: ",
        paste(sort(unknown), collapse = ", ")
      )
    }
  }
}

# V4. A rule whose id is defined but carried by no column can never match --
# the replacement for the retired (table_id, column_name) orphan check.
if (!is.null(ds)) {
  carried <- unique(ds$column_id[!blank(ds$column_id)])
  for (tn in names(rule_ids())) {
    orphans <- setdiff(unique(rule_ids()[[tn]]), carried)
    if (length(orphans) > 0) {
      fail(
        tn,
        ": rule(s) for column_id(s) on no database_structure row, so they can ",
        "never match: ",
        paste(sort(orphans), collapse = ", ")
      )
    }
  }
}

# V5 / V6. The converse: an id no column carries. Carrying a rule makes it a
# FAIL for the same reason as V4, read from the other end; carrying none is
# just an id defined ahead of the column that will use it.
if (!is.null(ds) && !is.null(ci)) {
  carried <- unique(ds$column_id[!blank(ds$column_id)])
  unused <- setdiff(ci$column_id, carried)
  ruled <- unique(unlist(rule_ids(), use.names = FALSE))
  unused_ruled <- intersect(unused, ruled)
  if (length(unused_ruled) > 0) {
    fail(
      "column_ids: ",
      length(unused_ruled),
      " id(s) are carried by no column but have rules: ",
      paste(sort(unused_ruled), collapse = ", ")
    )
  }
  unused_bare <- setdiff(unused, ruled)
  if (length(unused_bare) > 0) {
    message(
      "  column_ids: ",
      length(unused_bare),
      " id(s) defined but carried by no column (no rules either): ",
      paste(sort(unused_bare), collapse = ", ")
    )
  }
}

# V7. How far each id reaches. Nothing can detect PARTIAL under-assignment --
# an id applied to three of the five columns that should share it is
# self-consistent -- so the reach is printed for review instead.
#
# V8. The one mechanical cross-check available: columns sharing an id must
# agree on data_type. A disagreement means one of them is mis-assigned.
if (!is.null(ds)) {
  known <- ds[!blank(ds$column_id), , drop = FALSE]
  message("\n  column_id reach:")
  for (cid in sort(unique(known$column_id))) {
    rows <- known[known$column_id == cid, , drop = FALSE]
    message(
      "    ",
      cid,
      " -> ",
      nrow(rows),
      " column(s) in ",
      length(unique(rows$table_id)),
      " table(s)"
    )
    types <- unique(stats::na.omit(rows$data_type))
    if (length(types) > 1L) {
      fail(
        "database_structure: column_id '",
        cid,
        "' spans disagreeing data_type(s) ",
        paste(types, collapse = ", "),
        ": ",
        paste0(rows$table_id, ".", rows$column_name, collapse = ", "),
        " -- one of these columns is mis-assigned"
      )
    }
  }
  message("")
}

# --- numeric_ranges ---------------------------------------------------------

# The closed operator set is the package's, read from the loaded namespace so
# the two cannot drift. A scope_type outside it is not applied at all.
scope_types <- tryCatch(
  get(".qc_scope_types", envir = ns),
  error = function(e) {
    c(
      "taxon_within",
      "taxon_not_within",
      "in_functional_group",
      "not_in_functional_group"
    )
  }
)

# The same arrangement for the labelset narrowing a `column_lookups` row may
# carry. Separate from `scope_types` because the two tables accept different
# operators: a lookup binding narrows a permitted SET, so it has no use for the
# negations a numeric range scope needs.
lookup_scope_types <- tryCatch(
  get(".qc_lookup_scope_types", envir = ns),
  error = function(e) "in_labelset"
)

# A labelset reference is `tree:Label` or `tree:type=<value>`. Shape only --
# section 2b resolves it against the live registry.
lookup_ref_ok <- function(ref) {
  parts <- strsplit(ref, ":", fixed = TRUE)[[1]]
  if (length(parts) < 2L || !nzchar(trimws(parts[[1]]))) {
    return(FALSE)
  }
  rest <- trimws(paste(parts[-1], collapse = ":"))
  if (!nzchar(rest)) {
    return(FALSE)
  }
  # `type=` with nothing after it would select every untyped node in the tree.
  !startsWith(rest, "type=") || nzchar(trimws(sub("^type=", "", rest)))
}

# One `|`-separated reference, checked for shape only -- section 2b resolves it
# against the live registry.
ref_ok <- function(ref, scope_type) {
  if (startsWith(scope_type, "taxon_") && grepl("^urn:lsid:", ref)) {
    return(grepl("^urn:lsid:marinespecies\\.org:taxname:[0-9]+$", ref))
  }
  parts <- strsplit(ref, ":", fixed = TRUE)[[1]]
  length(parts) == 2L &&
    nzchar(trimws(parts[[1]])) &&
    nzchar(trimws(parts[[2]]))
}

if (!is.null(nr)) {
  scope_type <- ifelse(blank(nr$scope_type), "", trimws(nr$scope_type))
  scope_value <- ifelse(blank(nr$scope_value), "", trimws(nr$scope_value))

  # V9.
  bad_st <- setdiff(unique(scope_type[nzchar(scope_type)]), scope_types)
  if (length(bad_st) > 0) {
    fail(
      "numeric_ranges: unknown scope_type(s): ",
      paste(bad_st, collapse = ", "),
      " (allowed: ",
      paste(scope_types, collapse = ", "),
      ", or blank for an unconditional rule)"
    )
  }

  # V10. Either both scope columns are set or neither is. A scope_type with no
  # value is a rule the engine refuses to apply; a value with no type is a
  # restriction its author believes is in force and that nothing enforces.
  half <- which(xor(nzchar(scope_type), nzchar(scope_value)))
  if (length(half) > 0) {
    fail(
      "numeric_ranges: ",
      length(half),
      " row(s) set one of scope_type/scope_value and not the other: ",
      paste0(
        nr$column_id[half],
        " (scope_type '",
        scope_type[half],
        "', scope_value '",
        scope_value[half],
        "')",
        collapse = ", "
      )
    )
  }

  # V11. The grammar each scope_type accepts, per `|`-segment: a clade is
  # `Rank:Name` or a full marinespecies LSID; a functional group is
  # `tree:Label`, and the tree prefix is required because 540 of 1,579 labels
  # occur in more than one tree.
  scoped <- which(nzchar(scope_type) & nzchar(scope_value))
  for (i in scoped) {
    if (!scope_type[i] %in% scope_types) {
      next
    }
    refs <- trimws(strsplit(scope_value[i], "|", fixed = TRUE)[[1]])
    refs <- refs[nzchar(refs)]
    bad <- refs[!vapply(refs, ref_ok, logical(1), scope_type = scope_type[i])]
    if (length(bad) > 0) {
      fail(
        "numeric_ranges: rule '",
        nr_id[i],
        "' has malformed scope_value segment(s): ",
        paste(bad, collapse = ", "),
        " -- ",
        if (startsWith(scope_type[i], "taxon_")) {
          "expected 'Rank:Name' (e.g. Genus:Zostera) or a full LSID"
        } else {
          "expected 'tree:Label' (e.g. vegetation:Marine Seagrass)"
        }
      )
    }
  }

  # V16. The uniqueness key, deliberately excluding range_type: two rows for
  # one column and scope differing only in range_type is nonsense.
  key <- paste(nr$column_id, scope_type, scope_value, sep = "\u001f")
  dup <- unique(key[duplicated(key)])
  if (length(dup) > 0) {
    fail(
      "numeric_ranges: duplicate (column_id, scope_type, scope_value): ",
      paste(gsub("\u001f", " / ", dup), collapse = "; ")
    )
  }

  # V13. The derived rule_id, which the slug can collide even when the authored
  # tuple above is unique. The generator stops on this; here it is reported
  # alongside everything else.
  dup_rid <- unique(nr_id[duplicated(nr_id)])
  if (length(dup_rid) > 0) {
    fail(
      "numeric_ranges: derived rule_id(s) collide: ",
      paste(dup_rid, collapse = ", "),
      " -- the slug discards everything outside [a-z0-9], so two scope values ",
      "differing only in punctuation cannot be told apart in issues$rule_id"
    )
  }

  # V20, carried over from the table-keyed block with rule_id in the messages.
  bad_rt <- setdiff(stats::na.omit(unique(nr$range_type)), range_types)
  if (length(bad_rt) > 0) {
    fail(
      "numeric_ranges: unknown range_type(s): ",
      paste(bad_rt, collapse = ", ")
    )
  }
  bounds <- c("max_fail", "min_fail", "max_warn", "min_warn")
  has_bound <- rowSums(!is.na(nr[, bounds])) > 0

  # .qc_resolve_rules() in the package DROPS rows with an NA range_type, so a
  # row that sets bounds and leaves range_type empty reads as a live rule to its
  # author and as nothing to the engine. The inert placeholder rows the old
  # table carried are now column-ids/ rows with no rule, so a bound-less row
  # here is no longer tolerated either way.
  if (any(is.na(nr$range_type) & has_bound)) {
    i <- which(is.na(nr$range_type) & has_bound)
    fail(
      "numeric_ranges: ",
      length(i),
      " row(s) set bounds but leave range_type empty, so the rule is silently ",
      "dropped: ",
      paste(nr_id[i], collapse = ", "),
      " -- set range_type to inclusive/exclusive, or clear the bounds"
    )
  }
  if (any(!has_bound)) {
    i <- which(!has_bound)
    fail(
      "numeric_ranges: ",
      length(i),
      " row(s) declare no bound at all: ",
      paste(nr_id[i], collapse = ", "),
      " -- a range with nothing to compare against belongs in column-ids/ ",
      "with no rule"
    )
  }
  inverted <- which(
    (!is.na(nr$min_fail) & !is.na(nr$max_fail) & nr$min_fail > nr$max_fail) |
      (!is.na(nr$min_warn) & !is.na(nr$max_warn) & nr$min_warn > nr$max_warn)
  )
  if (length(inverted) > 0) {
    fail(
      "numeric_ranges: min above max on rule(s): ",
      paste(nr_id[inverted], collapse = ", ")
    )
  }

  # V19. A scoped rule's predicate column is always `scientific_name`, so a
  # scope reaching a table that has no such column resolves to an all-FALSE
  # mask and passes cleanly forever. Three of the ranged tables have no
  # scientific_name column, which is what makes this check mandatory rather
  # than defensive.
  if (!is.null(ds)) {
    assigned <- ds[!blank(ds$column_id), , drop = FALSE]
    has_sci <- unique(ds$table_id[ds$column_name == "scientific_name"])
    for (i in scoped) {
      reach <- unique(
        assigned$table_id[assigned$column_id == nr$column_id[i]]
      )
      missing_sci <- setdiff(reach, has_sci)
      if (length(missing_sci) > 0) {
        fail(
          "numeric_ranges: scoped rule '",
          nr_id[i],
          "' reaches table(s) with no scientific_name column, where the scope ",
          "can never match: ",
          paste(sort(missing_sci), collapse = ", ")
        )
      }
    }
  }
}

# --- controlled_vocabularies ------------------------------------------------

if (!is.null(cv)) {
  bad_v <- blank(cv$value)
  if (any(bad_v)) {
    fail(
      "controlled_vocabularies: ",
      sum(bad_v),
      " row(s) with an empty value: ",
      paste(unique(cv$column_id[bad_v]), collapse = ", ")
    )
  }
  # V17.
  key <- paste(cv$column_id, cv$value, sep = "\u001f")
  dup <- unique(key[duplicated(key)])
  if (length(dup) > 0) {
    fail(
      "controlled_vocabularies: duplicate (column_id, value): ",
      paste(gsub("\u001f", " / ", dup), collapse = "; ")
    )
  }
}

# --- column_lookups ---------------------------------------------------------
#
# V18. This table replaced a hardcoded list in the package, so a typo in it is
# now an authoring mistake rather than a compile error -- and a lookup naming a
# registry or field that does not exist binds nothing, which reads as a column
# with no registry QC. That is exactly the shape of the RLS opt-out, so the two
# have to be distinguishable: absence is intentional, a bad name is not.
if (!is.null(cl)) {
  dup <- unique(cl$column_id[duplicated(cl$column_id)])
  if (length(dup) > 0) {
    fail(
      "column_lookups: duplicate column_id (one registry binding per id): ",
      paste(dup, collapse = ", ")
    )
  }
  # The rule tables are published in the same manifest but are not registries;
  # binding a column to one of them is never meaningful.
  published <- setdiff(
    names(
      jsonlite::fromJSON(
        file.path(root, "dist", "manifest.json"),
        simplifyVector = FALSE
      )$table_index
    ),
    names(mg_rule_tables)
  )
  for (i in seq_len(nrow(cl))) {
    rt <- cl$registry_table[i]
    rc <- cl$registry_column[i]
    if (blank(rt) || blank(rc)) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' leaves registry_table or registry_column blank"
      )
      next
    }
    if (!rt %in% published) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' names registry_table '",
        rt,
        "', which dist/ does not publish as a registry (published: ",
        paste(sort(published), collapse = ", "),
        ")"
      )
      next
    }
    reg <- tryCatch(
      get(".mg_get_registry_table", envir = ns)(rt),
      error = function(e) {
        fail(
          "column_lookups: could not read registry '",
          rt,
          "': ",
          conditionMessage(e)
        )
        NULL
      }
    )
    if (is.null(reg)) {
      next
    }
    if (!rc %in% colnames(reg)) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' names registry_column '",
        rc,
        "', which is not a column of '",
        rt,
        "' (has: ",
        paste(colnames(reg), collapse = ", "),
        ")"
      )
    }
  }

  # V20. The optional labelset narrowing. A binding with no scope admits the
  # whole registry column, which is the long-standing behaviour; a binding WITH
  # one admits only the names the labelset places beneath the reference, so a
  # scope that cannot be resolved is the difference between "oysters are
  # rejected in a seagrass table" and "they are not". The engine degrades such a
  # scope to no narrowing at all -- the permissive direction -- which is exactly
  # why it has to fail here instead.
  lk_scope_type <- ifelse(blank(cl$scope_type), "", trimws(cl$scope_type))
  lk_scope_value <- ifelse(blank(cl$scope_value), "", trimws(cl$scope_value))

  bad_st <- setdiff(unique(lk_scope_type[nzchar(lk_scope_type)]), lookup_scope_types)
  if (length(bad_st) > 0) {
    fail(
      "column_lookups: unknown scope_type(s): ",
      paste(bad_st, collapse = ", "),
      ". Valid: ",
      paste(lookup_scope_types, collapse = ", ")
    )
  }

  # Either both scope columns are set or neither is, as in numeric_ranges: a
  # scope_value with no scope_type is metadata nothing can act on.
  half <- which(xor(nzchar(lk_scope_type), nzchar(lk_scope_value)))
  if (length(half) > 0) {
    fail(
      "column_lookups: ",
      length(half),
      " row(s) set one of scope_type/scope_value and not the other: ",
      paste0(
        cl$column_id[half],
        " (scope_type '",
        lk_scope_type[half],
        "', scope_value '",
        lk_scope_value[half],
        "')",
        collapse = "; "
      )
    )
  }

  for (i in which(nzchar(lk_scope_type) & nzchar(lk_scope_value))) {
    if (!lk_scope_type[i] %in% lookup_scope_types) {
      next
    }
    refs <- trimws(strsplit(lk_scope_value[i], "|", fixed = TRUE)[[1]])
    refs <- refs[nzchar(refs)]
    bad <- refs[!vapply(refs, lookup_ref_ok, logical(1))]
    if (length(bad) > 0) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' has malformed scope_value segment(s): ",
        paste(bad, collapse = ", "),
        ". Expected 'tree:Label' or 'tree:type=<value>'"
      )
      next
    }

    # Narrowing works by intersecting the registry's `scientific_id` against the
    # ids the labelset places beneath the reference, so a registry without that
    # column can only ever narrow to nothing.
    reg <- tryCatch(
      get(".mg_get_registry_table", envir = ns)(cl$registry_table[i]),
      error = function(e) NULL
    )
    if (!is.null(reg) && !"scientific_id" %in% colnames(reg)) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' carries a labelset scope but is bound to registry '",
        cl$registry_table[i],
        "', which has no scientific_id column to intersect on"
      )
    }
  }
}

# Row order is semantic -- qc_check_columns() reports column ORDER issues --
# and it is decided by nothing more than the sorted filenames. Assert that the
# order on disk still reproduces what dist/ was built from.
if (!is.null(ds) && file.exists(file.path(root, "dist", "qc-metadata.json"))) {
  published <- jsonlite::fromJSON(
    file.path(root, "dist", "qc-metadata.json"),
    simplifyVector = FALSE
  )$tables$database_structure
  pub_key <- vapply(
    published,
    function(r) paste0(r$table_id, "\u001f", r$column_name),
    character(1)
  )
  disk_key <- paste(ds$table_id, ds$column_name, sep = "\u001f")
  if (!identical(pub_key, disk_key)) {
    first <- which(pub_key[seq_along(disk_key)] != disk_key)[1]
    fail(
      "database_structure: row order on disk does not match dist/ (first ",
      "difference at row ",
      first,
      "). Column order is part of the contract; regenerate dist/."
    )
  } else {
    message("  database_structure row order matches dist/")
  }
}

# ---------------------------------------------------------------------------
# 2b. Does every scope reference resolve against the live registry?
# ---------------------------------------------------------------------------
#
# Section 2 checked the GRAMMAR of each scope_value. This resolves it for real,
# through the same expansion the QC engine uses, against the registries this
# working tree publishes. An unresolvable or ambiguous reference degrades to a
# runtime warning and an all-FALSE mask inside the engine -- a rule that never
# fires and never complains -- so it has to fail before the merge instead.

message("\n== scope references ==")

expand <- get("utl_mg_expand_taxon_set", envir = ns)

if (is.null(nr)) {
  message("  numeric_ranges unavailable; nothing to resolve")
} else {
  scoped_rows <- which(
    !blank(nr$scope_type) &
      !blank(nr$scope_value) &
      trimws(nr$scope_type) %in% scope_types
  )
  if (length(scoped_rows) == 0L) {
    message("  no scoped rules")
  }
  seen <- character(0)
  for (i in scoped_rows) {
    st <- trimws(nr$scope_type[i])
    sv <- trimws(nr$scope_value[i])
    key <- paste(st, sv, sep = "\u001f")
    if (key %in% seen) {
      next
    }
    seen <- c(seen, key)

    refs <- trimws(strsplit(sv, "|", fixed = TRUE)[[1]])
    refs <- refs[nzchar(refs)]
    hierarchy <- if (startsWith(st, "taxon_")) {
      "taxonomy"
    } else {
      "functional_group"
    }

    # The expansion warns rather than errors on an unresolved or ambiguous
    # reference, and then returns zero rows -- so the warning carries the
    # reason and has to be promoted here.
    warned <- character(0)
    got <- tryCatch(
      withCallingHandlers(
        expand(refs, hierarchy = hierarchy),
        warning = function(w) {
          warned <<- c(warned, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) {
        fail(
          "numeric_ranges: scope '",
          st,
          " = ",
          sv,
          "' could not be expanded: ",
          conditionMessage(e)
        )
        NULL
      }
    )
    if (is.null(got)) {
      next
    }
    if (length(warned) > 0) {
      fail(
        "numeric_ranges: scope '",
        st,
        " = ",
        sv,
        "': ",
        paste(unique(warned), collapse = " | ")
      )
      next
    }
    if (nrow(got) == 0L) {
      fail(
        "numeric_ranges: scope '",
        st,
        " = ",
        sv,
        "' expands to no taxa, so the rule can never fire"
      )
      next
    }
    message("  ", st, " = ", sv, " -> ", nrow(got), " taxon/taxa")
  }
}

# The same resolution for the labelset scopes on `column_lookups`, which narrow
# a permitted name set rather than a rule's row mask. A reference that resolves
# to nothing here would leave the engine admitting the whole registry column,
# so an empty expansion is a failure rather than an empty set.
if (is.null(cl)) {
  message("  column_lookups unavailable; nothing to resolve")
} else {
  lk_scoped <- which(
    !blank(cl$scope_type) &
      !blank(cl$scope_value) &
      trimws(cl$scope_type) %in% lookup_scope_types
  )
  if (length(lk_scoped) == 0L) {
    message("  no scoped lookups")
  }
  for (i in lk_scoped) {
    sv <- trimws(cl$scope_value[i])
    refs <- trimws(strsplit(sv, "|", fixed = TRUE)[[1]])
    refs <- refs[nzchar(refs)]

    warned <- character(0)
    got <- tryCatch(
      withCallingHandlers(
        expand(refs, hierarchy = "functional_group"),
        warning = function(w) {
          warned <<- c(warned, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) {
        fail(
          "column_lookups: '",
          cl$column_id[i],
          "' scope '",
          sv,
          "' could not be expanded: ",
          conditionMessage(e)
        )
        NULL
      }
    )
    if (is.null(got)) {
      next
    }
    if (length(warned) > 0) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' scope '",
        sv,
        "': ",
        paste(unique(warned), collapse = " | ")
      )
      next
    }
    if (nrow(got) == 0L) {
      fail(
        "column_lookups: '",
        cl$column_id[i],
        "' scope '",
        sv,
        "' expands to no taxa, so the column would admit no value at all"
      )
      next
    }
    message(
      "  ",
      cl$column_id[i],
      " = ",
      sv,
      " -> ",
      nrow(got),
      " permitted name(s)"
    )
  }
}

# ---------------------------------------------------------------------------
# 3. Do the registry tables pass their own QC rules?
# ---------------------------------------------------------------------------

message("\n== registry tables ==")

read_table <- function(table_path, label) {
  tryCatch(
    readr::read_csv(
      list.files(table_path, full.names = TRUE),
      show_col_types = FALSE,
      progress = FALSE
    ),
    error = function(e) {
      fail(label, ": error reading CSV - ", conditionMessage(e))
      NULL
    }
  )
}

registries <- list(
  observation_lookup = list(
    path = "./taxonomy-and-functional-groups/observation-lookup/",
    label = "Observation Lookup Table"
  ),
  taxonomic_lookup = list(
    path = "./taxonomy-and-functional-groups/taxonomic-lookup/",
    label = "Taxonomic Lookup Table"
  ),
  nested_labelsets = list(
    path = "./taxonomy-and-functional-groups/nested-labelsets/",
    label = "Nested Labelsets Table"
  ),
  site_lookup = list(
    path = "./sites-and-partners/site-names/",
    label = "MarineGEO Site Lookup Table"
  ),
  partner_lookup = list(
    path = "./sites-and-partners/partner-codes/",
    label = "MarineGEO Partner Lookup Table"
  )
)

for (table_id in names(registries)) {
  spec <- registries[[table_id]]
  data <- read_table(spec$path, spec$label)
  if (is.null(data)) {
    next
  }

  tryCatch(
    {
      result <- marinegeo.utils::qc_run(data, table_id = table_id) |>
        dplyr::filter(severity == "fail")
      if (nrow(result) == 0) {
        message("  ", spec$label, ": no failures")
      } else {
        message("  ", spec$label, ":")
        print(result)
        fail(spec$label, ": ", nrow(result), " QC failure(s)")
      }
    },
    error = function(e) fail(spec$label, ": ", conditionMessage(e))
  )
}

# ---------------------------------------------------------------------------
# 4. Functional group assignment
# ---------------------------------------------------------------------------

message("\n== functional group assignment ==")

tryCatch(
  {
    groups <- c("Seagrass", "Algae")
    got <- marinegeo.utils::utl_mg_assign_functional_groups(
      "vegetation",
      groups,
      c("Zostera marina", "unidentified macroalgae")
    )
    if (all(got == groups)) {
      message("  seagrass functional group test: passed")
    } else {
      fail(
        "seagrass functional group test returned: ",
        paste(got, collapse = ", ")
      )
    }
  },
  error = function(e) {
    fail("seagrass functional group test: ", conditionMessage(e))
  }
)

# ---------------------------------------------------------------------------
# 5. End-to-end: does a scoped range rule actually fire?
# ---------------------------------------------------------------------------
#
# Section 3 runs qc_run() over the registry tables, none of which has a ranged
# column, so nothing above exercises the scope machinery end to end. The
# fixture below is three rows against the real published rules: a Zostera leaf
# inside the band, a Zostera leaf below it, and a Halodule leaf of the same
# length that must NOT be judged against Zostera bounds.
#
# The failure this guards against is the whole reason the scope mask returns
# all-FALSE on every error path: a broken scope that silently stops matching
# looks exactly like clean data.

message("\n== scoped range smoke test ==")

smoke_table <- "seagrass-leaf-monitoring-v1"
smoke <- data.frame(
  scientific_name = c("Zostera marina", "Zostera marina", "Halodule wrightii"),
  leaf_length_mm = c(600, 5, 5),
  stringsAsFactors = FALSE
)

tryCatch(
  {
    issues <- marinegeo.utils::qc_run(
      smoke,
      table_id = smoke_table,
      partial = TRUE,
      verbose = FALSE
    )
    ranged <- issues[issues$check == "qc_check_numeric_ranges", , drop = FALSE]
    scoped <- ranged[grepl("__taxon_within__", ranged$rule_id), , drop = FALSE]
    if (nrow(scoped) == 1L && identical(as.integer(scoped$row), 2L)) {
      message(
        "  Genus:Zostera leaf band fired on row 2 only (",
        scoped$rule_id,
        ")"
      )
    } else {
      fail(
        "scoped range smoke test: expected exactly one Genus:Zostera range ",
        "issue, on row 2 (the 5 mm Zostera leaf), and none on row 3 (the 5 mm ",
        "Halodule leaf). Got ",
        nrow(scoped),
        " issue(s) on row(s) ",
        if (nrow(scoped) == 0L) {
          "none"
        } else {
          paste(scoped$row, collapse = ", ")
        }
      )
    }
  },
  error = function(e) {
    fail("scoped range smoke test: ", conditionMessage(e))
  }
)

# ---------------------------------------------------------------------------

message("")
if (length(failures) > 0) {
  message("== ", length(failures), " failure(s) ==")
  for (f in failures) {
    message("  - ", f)
  }
  quit(status = 1L)
}
message("== all checks passed ==")
