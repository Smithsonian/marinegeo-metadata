# Validate this repo's metadata against its own QC rules.
#
# Run from the repo root:
#   Rscript R/validate.R
#
# Exits non-zero on any failure
#
# Three things are checked, in order:
#   1. dist/ is current with respect to the authored sources.
#   2. The authored rule-table CSVs are well formed and cross-referentially
#      complete.
#   3. The registry lookup tables pass the QC rules they themselves declare.

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

# `.mg_registry_required_cols` is the discriminator: an installed build from
# before the rule tables were cut back to three still has the schema-version
# symbols, so probing for those alone accepts a package that then reports every
# registry table as missing a `condition_id` column that no longer exists.
.needed <- c(
  ".mg_dist_schema_version",
  ".mg_dist_schema_version_min",
  ".mg_registry_required_cols"
)
.has_new_api <- function() {
  ns <- tryCatch(asNamespace("marinegeo.utils"), error = function(e) NULL)
  !is.null(ns) &&
    all(vapply(.needed, exists, logical(1), envir = ns, inherits = FALSE))
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
  "functional_group_lookup",
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

# A rule keyed to a (table_id, column_name) that database_structure does not
# describe can never match a column, so it never fires. The nested YAML made
# this unrepresentable -- rules hung off the column they applied to; flat CSVs
# lose that guarantee, so it is checked explicitly.
if (!is.null(ds)) {
  known <- paste(ds$table_id, ds$column_name, sep = "\u001f")
  for (tn in c("categorical_values", "numeric_ranges")) {
    tbl <- rules[[tn]]
    if (is.null(tbl)) {
      next
    }
    keys <- paste(tbl$table_id, tbl$column_name, sep = "\u001f")
    orphans <- unique(keys[!keys %in% known])
    if (length(orphans) > 0) {
      fail(
        tn,
        ": rule(s) for column(s) not in database_structure: ",
        paste(sub("\u001f", ".", orphans), collapse = ", ")
      )
    }
  }
}

nr <- rules$numeric_ranges
if (!is.null(nr)) {
  bad_rt <- setdiff(stats::na.omit(unique(nr$range_type)), range_types)
  if (length(bad_rt) > 0) {
    fail(
      "numeric_ranges: unknown range_type(s): ",
      paste(bad_rt, collapse = ", ")
    )
  }
  bounds <- c("max_fail", "min_fail", "max_warn", "min_warn")
  has_bound <- rowSums(!is.na(nr[, bounds])) > 0

  # .qc_resolve_rules() in the package DROPS rows with an NA range_type. A row
  # that also sets no bound declares nothing and is a harmless placeholder for a
  # range nobody has decided yet -- the authored YAML spelled it `range_type: ~`.
  # A row that sets bounds and leaves range_type empty is the dangerous case:
  # it reads as a live rule to its author and as nothing to the engine.
  skipped <- is.na(nr$range_type) & has_bound
  if (any(skipped)) {
    fail(
      "numeric_ranges: ",
      sum(skipped),
      " row(s) set bounds but leave range_type empty, so the rule is silently ",
      "dropped: ",
      paste(
        paste0(nr$table_id[skipped], ".", nr$column_name[skipped]),
        collapse = ", "
      ),
      " -- set range_type to inclusive/exclusive, or clear the bounds"
    )
  }
  placeholders <- is.na(nr$range_type) & !has_bound
  if (any(placeholders)) {
    message(
      "  numeric_ranges: ",
      sum(placeholders),
      " placeholder row(s) declare no bounds (no range_type, no bounds)"
    )
  }
  # The mirror image: a declared range_type with nothing to compare against.
  if (any(!is.na(nr$range_type) & !has_bound)) {
    fail(
      "numeric_ranges: row(s) declare a range_type but set no bound: ",
      paste(
        paste0(
          nr$table_id[!is.na(nr$range_type) & !has_bound],
          ".",
          nr$column_name[!is.na(nr$range_type) & !has_bound]
        ),
        collapse = ", "
      )
    )
  }
  inverted <- which(
    (!is.na(nr$min_fail) & !is.na(nr$max_fail) & nr$min_fail > nr$max_fail) |
      (!is.na(nr$min_warn) & !is.na(nr$max_warn) & nr$min_warn > nr$max_warn)
  )
  if (length(inverted) > 0) {
    fail(
      "numeric_ranges: min above max on row(s): ",
      paste(
        paste0(nr$table_id[inverted], ".", nr$column_name[inverted]),
        collapse = ", "
      )
    )
  }
  key <- paste(nr$table_id, nr$column_name, nr$range_type)
  dup <- unique(key[duplicated(key)])
  if (length(dup) > 0) {
    fail(
      "numeric_ranges: duplicate (table_id, column_name, range_type): ",
      paste(dup, collapse = "; ")
    )
  }
}

cv <- rules$categorical_values
if (!is.null(cv)) {
  blank <- is.na(cv$value) | !nzchar(trimws(cv$value))
  if (any(blank)) {
    fail(
      "categorical_values: ",
      sum(blank),
      " row(s) with an empty value: ",
      paste(
        unique(paste0(cv$table_id[blank], ".", cv$column_name[blank])),
        collapse = ", "
      )
    )
  }
  key <- paste(cv$table_id, cv$column_name, cv$value)
  dup <- unique(key[duplicated(key)])
  if (length(dup) > 0) {
    fail(
      "categorical_values: duplicate (table_id, column_name, value): ",
      paste(dup, collapse = "; ")
    )
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
  functional_group_lookup = list(
    path = "./taxonomy-and-functional-groups/functional-group-lookup/",
    label = "Functional Group/Morphological Lookup Table"
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

message("")
if (length(failures) > 0) {
  message("== ", length(failures), " failure(s) ==")
  for (f in failures) {
    message("  - ", f)
  }
  quit(status = 1L)
}
message("== all checks passed ==")
