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
      "uuid_identity",
      "column_id"
    )
  ),
  column_ids = list(
    dir = "table-metadata/column-ids",
    cols = c("column_id", "label", "definition", "unit")
  ),
  numeric_ranges = list(
    dir = "table-metadata/numeric-ranges",
    cols = c(
      "column_id",
      "scope_type",
      "scope_value",
      "range_type",
      "max_fail",
      "min_fail",
      "max_warn",
      "min_warn"
    )
  ),
  controlled_vocabularies = list(
    dir = "table-metadata/controlled-vocabularies",
    cols = c("column_id", "value")
  ),
  column_lookups = list(
    dir = "table-metadata/column-lookups",
    cols = c("column_id", "registry_table", "registry_column")
  )
)

# `rule_id` is NOT authored and so is absent from the header above. The generator
# derives it from (column_id, scope_type, scope_value) and writes it into the
# published numeric_ranges table only, so this list describes the CSVs while the
# package's `.mg_registry_required_cols` describes the published bundle, which
# carries the extra column. That is the one place the two diverge.
#
# The derivation slugs the scope, which is lossy, so the generator checks the
# derived ids for collisions itself -- the uniqueness key on the authored tuple
# is not sufficient to guarantee them unique.

# Types are declared, never guessed. readr guesses from a sample taken across a
# multi-file read, so an all-empty column in the first-sorted file decides the
# type for every later one: `uuid_identity` would come back character the day
# darwin-core has no TRUE in it, and `which()` on it in the package's QC engine
# would stop working. `value` holds the literal strings "TRUE"/"FALSE", which
# must stay text. Two live instances of the same trap in the new tables:
# `definition` is empty on every column-ids row today, and `scope_type` /
# `scope_value` are empty on 29 of the 30 numeric-ranges rows -- readr would
# guess logical for all three.
mg_rule_col_types <- list(
  database_structure = readr::cols(
    protocol = readr::col_character(),
    table_id = readr::col_character(),
    column_name = readr::col_character(),
    data_type = readr::col_character(),
    missing_values = readr::col_character(),
    uuid_identity = readr::col_logical(),
    column_id = readr::col_character()
  ),
  column_ids = readr::cols(
    column_id = readr::col_character(),
    label = readr::col_character(),
    definition = readr::col_character(),
    unit = readr::col_character()
  ),
  numeric_ranges = readr::cols(
    column_id = readr::col_character(),
    scope_type = readr::col_character(),
    scope_value = readr::col_character(),
    range_type = readr::col_character(),
    max_fail = readr::col_double(),
    min_fail = readr::col_double(),
    max_warn = readr::col_double(),
    min_warn = readr::col_double()
  ),
  controlled_vocabularies = readr::cols(
    column_id = readr::col_character(),
    value = readr::col_character()
  ),
  column_lookups = readr::cols(
    column_id = readr::col_character(),
    registry_table = readr::col_character(),
    registry_column = readr::col_character()
  )
)

# `rule_id` derivation for `numeric_ranges`, shared with R/validate.R.
#
# Defined here rather than in the generator because both sides need it: the
# generator derives the ids it publishes, and the validator has to report the
# same ids in its messages and check them for collisions before a run that
# would stop() in the generator. Two copies of a lossy slug rule would drift.
#
# The slug collapses every run of non-alphanumerics to a single `_` and trims
# the ends, so it is lossy by design: `Genus:Zostera` and `Genus_Zostera` are
# different scope values that slug identically.
mg_rule_id_slug <- function(x) {
  gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(x)))
}

# `column_id` for an unconditional rule, `column_id__<scope_type>__<scope_value>`
# for a scoped one. Returns the id vector; the caller decides what a collision
# means.
mg_derive_rule_id <- function(tbl) {
  scoped <- !is.na(tbl$scope_type) & nzchar(tbl$scope_type)
  ifelse(
    scoped,
    paste(
      tbl$column_id,
      mg_rule_id_slug(tbl$scope_type),
      mg_rule_id_slug(tbl$scope_value),
      sep = "__"
    ),
    tbl$column_id
  )
}
