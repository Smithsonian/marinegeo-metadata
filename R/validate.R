# Validate this repo's metadata against its own QC rules.
#
# Run from the repo root:
#   Rscript R/validate.R
#
# Exits non-zero on any failure
#
# Three things are checked, in order:
#   1. dist/ is current with respect to the authored sources.
#   2. The authored YAML passes schema and cross-reference validation.
#   3. The registry lookup tables pass the QC rules they themselves declare.

library(readr, quietly = TRUE, warn.conflicts = FALSE)
library(dplyr, quietly = TRUE, warn.conflicts = FALSE)

root <- normalizePath(".", mustWork = TRUE)
failures <- character(0)

fail <- function(...) {
  msg <- paste0(...)
  failures <<- c(failures, msg)
  message("FAIL: ", msg)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# marinegeo.utils, new enough to read dist/
# ---------------------------------------------------------------------------

.needed <- c(".mg_validate_table_metadata", ".mg_parse_table_metadata_dir")
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
      "marinegeo.utils with table-metadata support is required ",
      "(install it, or set MARINEGEO_UTILS_PATH)"
    )
  }
  message("using marinegeo.utils from ", pkg)
  suppressMessages(pkgload::load_all(pkg, quiet = TRUE))
}
ns <- asNamespace("marinegeo.utils")

# Resolve registries from THIS working tree, not from the remote default
# branch -- otherwise an unmerged change validates against main and the run is
# meaningless. Strict mode turns a resolution failure into an error rather than
# a silent fall back to the bundled copy, which here would validate the wrong
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

  current <- c(
    list.files(file.path(root, "table-metadata"), pattern = "\\.ya?ml$", full.names = TRUE),
    list.files(file.path(root, "sites-and-partners"), pattern = "\\.csv$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(root, "taxonomy-and-functional-groups"), pattern = "\\.csv$", recursive = TRUE, full.names = TRUE),
    file.path(root, "marinegeo_data_index.csv")
  )
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
    for (f in added) message("  + ", f, " (not in manifest)")
    for (f in removed) message("  - ", f, " (in manifest, not on disk)")
    for (f in changed) message("  ~ ", f, " (changed since dist/ was built)")
    fail(
      "dist/ is stale. Run: Rscript R/generate-metadata-dist.R"
    )
  } else {
    message("  dist/ matches all ", length(rel), " source files")
  }
}

# ---------------------------------------------------------------------------
# 2. Does the authored YAML validate?
# ---------------------------------------------------------------------------

message("\n== table-metadata schema ==")

tryCatch(
  {
    docs <- get(".mg_parse_table_metadata_dir", envir = ns)(
      file.path(root, "table-metadata")
    )
    get(".mg_validate_table_metadata", envir = ns)(docs)
    message("  ", length(docs), " protocol file(s) valid")
  },
  error = function(e) fail("table-metadata: ", conditionMessage(e))
)

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
  error = function(e) fail("seagrass functional group test: ", conditionMessage(e))
)

# ---------------------------------------------------------------------------

message("")
if (length(failures) > 0) {
  message("== ", length(failures), " failure(s) ==")
  for (f in failures) message("  - ", f)
  quit(status = 1L)
}
message("== all checks passed ==")
