# Build the dist/ distribution JSON files from the authored sources.
#
# Run from the repo root:
#   Rscript R/generate-metadata-dist.R
#
# Sources, each in the format that suits its shape:
#   table-metadata/**/*.csv                  tabular, hand-authored rule tables
#   sites-and-partners/**/*.csv              tabular, hand-authored registries
#   taxonomy-and-functional-groups/**/*.csv  tabular, machine-generated adjacency
#   marinegeo_data_index.csv
#
# The manifest declares each table's column types. JSON cannot distinguish a
# null from a typed NA, so a column that is entirely null would otherwise be
# read back as the wrong type. Consumers coerce from the declared
# schema instead of guessing.

suppressPackageStartupMessages({
  library(readr)
})

root <- normalizePath(".", mustWork = TRUE)
stopifnot(dir.exists(file.path(root, "table-metadata")))

# The authored source list, the rule-table headers and their declared column
# types, shared with R/validate.R.
source(file.path(root, "R", "sources.R"))

SCHEMA_VERSION <- 1L

# Row order is semantic: the package's qc_check_columns() reports column ORDER
# issues against database_structure, so the sorted file order below is part of
# the contract, not an implementation detail.
read_dir <- function(sub, col_types = NULL) {
  files <- sort(list.files(
    file.path(root, sub),
    pattern = "\\.csv$",
    full.names = TRUE
  ))
  if (length(files) == 0L) {
    stop("no CSVs in '", sub, "'")
  }
  readr::read_csv(
    files,
    col_types = col_types,
    show_col_types = FALSE,
    progress = FALSE
  )
}

# ---------------------------------------------------------------------------
# Gather every table
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Encoding guard
# ---------------------------------------------------------------------------
#
# JSON must be valid UTF-8. Checked here, against the raw bytes, before
# anything is read or written.

check_utf8 <- function(paths) {
  bad <- list()
  for (p in paths) {
    raw <- readBin(p, "raw", file.size(p))
    txt <- rawToChar(raw)
    Encoding(txt) <- "UTF-8"
    if (!validUTF8(txt)) {
      offset <- which(raw > as.raw(127))[1]
      line <- sum(raw[seq_len(offset)] == as.raw(10)) + 1L
      bad[[length(bad) + 1L]] <- sprintf(
        "  %s (line %d, byte offset %d, value 0x%s -- '%s' in Latin-1)",
        sub(paste0("^", root, "/"), "", p),
        line,
        offset,
        format(raw[offset]),
        iconv(rawToChar(raw[offset]), "ISO-8859-1", "UTF-8")
      )
    }
  }
  if (length(bad) > 0) {
    stop(
      "\nsource file(s) are not valid UTF-8:\n",
      paste(unlist(bad), collapse = "\n"),
      "\n\nJSON bundles must be UTF-8, so this has to be fixed at source.",
      "\nTo repair one file in place:",
      "\n  iconv -f ISO-8859-1 -t UTF-8 <file> -o <file>.tmp && mv <file>.tmp <file>",
      call. = FALSE
    )
  }
}

# A UTF-8 BOM is valid UTF-8, so check_utf8() cannot see it. readr strips one
# from the FIRST file of a multi-file read, which is why BOMs have survived
# here unnoticed -- but on any other file the leading column name keeps the
# marker, and whether that matters depends on nothing more than sort order.
#
# For the rule tables that is a correctness problem: a mangled `table_id` or
# `protocol` header means the column is missing, and a missing column in a rule
# table reads downstream as "no rules" -- a clean QC pass that checked nothing.
# So BOMs are fatal there, and reported but tolerated elsewhere.
check_bom <- function(paths, fatal) {
  has_bom <- vapply(
    paths,
    function(p) {
      raw <- readBin(p, "raw", 3L)
      length(raw) == 3L && identical(raw, as.raw(c(0xEF, 0xBB, 0xBF)))
    },
    logical(1)
  )
  found <- sub(paste0("^", root, "/"), "", paths[has_bom])
  if (length(found) == 0) {
    return(invisible(NULL))
  }
  detail <- paste0(
    "\n  ",
    paste(found, collapse = "\n  "),
    "\n\nTo strip one in place:",
    "\n  sed -i '1s/^\\xef\\xbb\\xbf//' <file>"
  )
  if (fatal) {
    stop("\nrule-table CSV(s) start with a UTF-8 BOM:", detail, call. = FALSE)
  }
  warning(
    "source file(s) start with a UTF-8 BOM:",
    detail,
    call. = FALSE,
    immediate. = TRUE
  )
  invisible(NULL)
}

all_sources <- mg_source_files(root)
message("checking source encodings ...")
check_utf8(all_sources)
rule_csvs <- list.files(
  file.path(root, "table-metadata"),
  pattern = "\\.csv$",
  recursive = TRUE,
  full.names = TRUE
)
check_bom(rule_csvs, fatal = TRUE)
check_bom(setdiff(all_sources, rule_csvs), fatal = FALSE)

message("reading table-metadata CSVs ...")
# Built in the order the bundle has always carried these tables.
qc <- list()
for (tn in names(mg_rule_tables)) {
  spec <- mg_rule_tables[[tn]]
  tbl <- read_dir(spec$dir, mg_rule_col_types[[tn]])
  # The generator's half of the header contract; R/validate.R reports every
  # problem at once, this one refuses to publish.
  if (!identical(colnames(tbl), spec$cols)) {
    stop(
      "'",
      spec$dir,
      "' has columns ",
      paste(colnames(tbl), collapse = ", "),
      " but ",
      tn,
      " requires exactly ",
      paste(spec$cols, collapse = ", "),
      call. = FALSE
    )
  }
  qc[[tn]] <- tbl
  message("  ", spec$dir, "  ", nrow(tbl), " rows")
}

message("reading CSV registries ...")
sites <- list(
  partner_codes = read_dir("sites-and-partners/partner-codes"),
  site_codes = read_dir("sites-and-partners/site-names"),
  data_index = readr::read_csv(
    file.path(root, "marinegeo_data_index.csv"),
    show_col_types = FALSE,
    progress = FALSE
  )
)
taxonomy <- list(
  observation_lookup = read_dir(
    "taxonomy-and-functional-groups/observation-lookup"
  ),
  taxonomic_lookup = read_dir(
    "taxonomy-and-functional-groups/taxonomic-lookup"
  ),
  functional_group_lookup = read_dir(
    "taxonomy-and-functional-groups/functional-group-lookup"
  )
)

bundles <- list(
  `qc-metadata` = qc,
  sites = sites,
  taxonomy = taxonomy
)

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

dist <- file.path(root, "dist")
dir.create(dist, recursive = TRUE, showWarnings = FALSE)

expected <- c(
  "README.md",
  "manifest.json",
  paste0(names(bundles), ".json")
)

# `type` is what consumers coerce to; it is declared, never inferred.
col_type <- function(x) {
  if (is.logical(x)) {
    "logical"
  } else if (is.numeric(x)) {
    "double"
  } else if (inherits(x, "Date")) {
    "date"
  } else {
    "character"
  }
}

as_records <- function(d) {
  # Drop readr's spec/problems attributes so they do not reach the JSON.
  d <- as.data.frame(d)
  attr(d, "spec") <- NULL
  attr(d, "problems") <- NULL
  jsonlite::toJSON(
    d,
    dataframe = "rows",
    na = "null",
    auto_unbox = TRUE,
    digits = NA
  )
}

write_json_file <- function(txt, path) {
  writeLines(txt, path)
  invisible(path)
}

sha <- function(path) digest::digest(file = path, algo = "sha256")

table_schema <- function(d) {
  list(
    rows = nrow(d),
    columns = lapply(colnames(d), function(nm) {
      list(name = nm, type = col_type(d[[nm]]))
    })
  )
}

manifest_bundles <- list()
table_index <- list()

for (bname in names(bundles)) {
  tabs <- bundles[[bname]]

  body <- paste0(
    '{\n  "schema_version": ',
    SCHEMA_VERSION,
    ',\n  "bundle": "',
    bname,
    '",\n  "tables": {\n',
    paste(
      vapply(
        names(tabs),
        function(tn) paste0('    "', tn, '": ', as_records(tabs[[tn]])),
        character(1)
      ),
      collapse = ",\n"
    ),
    "\n  }\n}"
  )
  bpath <- file.path(dist, paste0(bname, ".json"))
  write_json_file(body, bpath)

  manifest_bundles[[bname]] <- list(
    path = paste0("dist/", bname, ".json"),
    sha256 = sha(bpath),
    bytes = file.size(bpath),
    tables = stats::setNames(lapply(tabs, table_schema), names(tabs))
  )

  for (tn in names(tabs)) {
    table_index[[tn]] <- bname
  }

  message(
    "  dist/",
    bname,
    ".json  ",
    format(file.size(bpath), big.mark = ","),
    " bytes, ",
    length(tabs),
    " tables"
  )
}

# Source hashes let CI prove dist/ was regenerated from the committed sources.
source_files <- all_sources
sources <- stats::setNames(
  lapply(source_files, sha),
  sub(paste0("^", root, "/"), "", source_files)
)

manifest <- list(
  schema_version = SCHEMA_VERSION,
  generated_at = format(
    as.POSIXct(Sys.time(), tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ"
  ),
  generator = "R/generate-metadata-dist.R",
  bundles = manifest_bundles,
  table_index = table_index,
  sources = sources
)
write_json_file(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  file.path(dist, "manifest.json")
)

stray <- setdiff(
  list.files(dist, recursive = TRUE),
  expected
)
if (length(stray) > 0) {
  warning(
    "unexpected file(s) in dist/ left in place: ",
    paste(stray, collapse = ", ")
  )
}

message(
  "wrote dist/manifest.json (",
  length(table_index),
  " tables across ",
  length(manifest_bundles),
  " bundles)"
)
