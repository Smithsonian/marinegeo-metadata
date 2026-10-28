# The authored source files dist/ is built from.
#
# Defined once and sourced by both R/generate-metadata-dist.R (to hash them into
# the manifest, and to check their encoding) and R/validate.R (to detect a
# dist/ that is stale with respect to them). Two copies of this list would drift
# the first time a directory is added, and a source missing from the manifest is
# a source whose edits never reach dist/.

mg_source_files <- function(root) {
  c(
    list.files(
      file.path(root, "table-metadata"),
      pattern = "\\.csv$",
      recursive = TRUE,
      full.names = TRUE
    ),
    list.files(
      file.path(root, "sites-and-partners"),
      pattern = "\\.csv$",
      recursive = TRUE,
      full.names = TRUE
    ),
    list.files(
      file.path(root, "taxonomy-and-functional-groups"),
      pattern = "\\.csv$",
      recursive = TRUE,
      full.names = TRUE
    ),
    file.path(root, "marinegeo_data_index.csv")
  )
}

# The authored rule tables, and the exact header each must carry.
#
# A rule table read with a missing or renamed column is read downstream as "no
# rules", which surfaces as a clean QC pass rather than an error -- so both the
# generator and the validator check the headers against this, and the package
# checks the published bundle against its own copy
# (`.mg_registry_required_cols` in R/api_mg_get_registries.R).
mg_rule_tables <- list(
  database_structure = list(
    dir = "table-metadata/data-structure",
    cols = c(
      "protocol",
      "table_id",
      "column_name",
      "data_type",
      "missing_values",
      "uuid_identity"
    )
  ),
  categorical_values = list(
    dir = "table-metadata/categorical-values",
    cols = c("table_id", "column_name", "value")
  ),
  numeric_ranges = list(
    dir = "table-metadata/numeric-ranges",
    cols = c(
      "table_id",
      "column_name",
      "range_type",
      "max_fail",
      "min_fail",
      "max_warn",
      "min_warn"
    )
  )
)

# Types are declared, never guessed. readr guesses from a sample taken across a
# multi-file read, so an all-empty column in the first-sorted file decides the
# type for every later one: `uuid_identity` would come back character the day
# darwin-core has no TRUE in it, and `which()` on it in the package's QC engine
# would stop working. `value` holds the literal strings "TRUE"/"FALSE", which
# must stay text.
mg_rule_col_types <- list(
  database_structure = readr::cols(
    protocol = readr::col_character(),
    table_id = readr::col_character(),
    column_name = readr::col_character(),
    data_type = readr::col_character(),
    missing_values = readr::col_character(),
    uuid_identity = readr::col_logical()
  ),
  categorical_values = readr::cols(
    table_id = readr::col_character(),
    column_name = readr::col_character(),
    value = readr::col_character()
  ),
  numeric_ranges = readr::cols(
    table_id = readr::col_character(),
    column_name = readr::col_character(),
    range_type = readr::col_character(),
    max_fail = readr::col_double(),
    min_fail = readr::col_double(),
    max_warn = readr::col_double(),
    min_warn = readr::col_double()
  )
)
