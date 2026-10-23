# Build the dist/ distribution JSON files from the authored sources.
#
# Run from the repo root:
#   Rscript R/generate-metadata-dist.R
#
# Sources, each in the format that suits its shape:
#   table-metadata/*.yaml                    nested, hand-authored rule configs
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

# The flattener lives in the R package so there is exactly one implementation,
# exercised by that package's round-trip test. This script is a thin wrapper.
pkg <- Sys.getenv(
  "MARINEGEO_UTILS_PATH",
  file.path(dirname(root), "marinegeo-R-utilities")
)
# An installed build may predate the flattener, so probe for the functions
# themselves rather than trusting that the namespace loads.
.needed <- c(
  ".mg_parse_table_metadata_dir",
  ".mg_flatten_table_metadata",
  ".mg_validate_table_metadata"
)

.grab <- function() {
  ns <- tryCatch(asNamespace("marinegeo.utils"), error = function(e) NULL)
  if (is.null(ns)) {
    return(NULL)
  }
  if (!all(vapply(.needed, exists, logical(1), envir = ns, inherits = FALSE))) {
    return(NULL)
  }
  stats::setNames(lapply(.needed, get, envir = ns, inherits = FALSE), .needed)
}

fns <- NULL
if (requireNamespace("marinegeo.utils", quietly = TRUE)) {
  fns <- .grab()
}
if (is.null(fns)) {
  if (!dir.exists(pkg)) {
    stop(
      "marinegeo.utils with the table-metadata flattener is required ",
      "(install it, or set MARINEGEO_UTILS_PATH to a local checkout)"
    )
  }
  message("using marinegeo.utils from ", pkg)
  suppressMessages(pkgload::load_all(pkg, quiet = TRUE))
  fns <- .grab()
  if (is.null(fns)) {
    stop("the checkout at ", pkg, " does not provide the flattener")
  }
}

parse_dir <- fns[[".mg_parse_table_metadata_dir"]]
flatten <- fns[[".mg_flatten_table_metadata"]]
validate <- fns[[".mg_validate_table_metadata"]]

SCHEMA_VERSION <- 1L

# An installed build that predates a schema bump still *has* the flattener, so
# the probe above accepts it -- and it then reads the current YAML as if every
# renamed key were absent, writing a well-formed dist/ full of nulls. Refuse a
# package that does not understand the schema we are about to publish.
.pkg_ver <- tryCatch(
  get(".mg_dist_schema_version", envir = asNamespace("marinegeo.utils")),
  error = function(e) NA_integer_
)
if (is.na(.pkg_ver) || .pkg_ver < SCHEMA_VERSION) {
  stop(
    "the marinegeo.utils in use understands dist schema ",
    .pkg_ver,
    " but this script publishes ",
    SCHEMA_VERSION,
    ". Install the current marinegeo.utils, or point MARINEGEO_UTILS_PATH at ",
    "a checkout that has it."
  )
}

read_dir <- function(sub) {
  files <- sort(list.files(
    file.path(root, sub),
    pattern = "\\.csv$",
    full.names = TRUE
  ))
  if (length(files) == 0L) {
    stop("no CSVs in '", sub, "'")
  }
  readr::read_csv(files, show_col_types = FALSE, progress = FALSE)
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
      "\n\nJSON artifacts must be UTF-8, so this has to be fixed at source.",
      "\nTo repair one file in place:",
      "\n  iconv -f ISO-8859-1 -t UTF-8 <file> -o <file>.tmp && mv <file>.tmp <file>",
      call. = FALSE
    )
  }
}

message("parsing table-metadata/*.yaml ...")
docs <- parse_dir(file.path(root, "table-metadata"))
# Refuse to publish anything that does not validate.
validate(docs)
qc <- flatten(docs)
message("  ", length(docs), " protocol files -> ", length(qc), " tables")

all_sources <- c(
  list.files(
    file.path(root, "table-metadata"),
    pattern = "\\.ya?ml$",
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
message("checking source encodings ...")
check_utf8(all_sources)

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

artifacts <- list(
  `qc-metadata` = qc,
  sites = sites,
  taxonomy = taxonomy
)

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

dist <- file.path(root, "dist")
tables_dir <- file.path(dist, "tables")
dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

expected <- c(
  "README.md",
  "manifest.json",
  paste0(names(artifacts), ".json"),
  file.path("tables", paste0(unlist(lapply(artifacts, names)), ".json"))
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

manifest_artifacts <- list()
table_index <- list()

for (aname in names(artifacts)) {
  tabs <- artifacts[[aname]]

  body <- paste0(
    '{\n  "schema_version": ',
    SCHEMA_VERSION,
    ',\n  "artifact": "',
    aname,
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
  apath <- file.path(dist, paste0(aname, ".json"))
  write_json_file(body, apath)

  manifest_artifacts[[aname]] <- list(
    path = paste0("dist/", aname, ".json"),
    sha256 = sha(apath),
    bytes = file.size(apath),
    tables = stats::setNames(lapply(tabs, table_schema), names(tabs))
  )

  for (tn in names(tabs)) {
    tpath <- file.path(tables_dir, paste0(tn, ".json"))
    write_json_file(
      paste0(
        '{\n  "schema_version": ',
        SCHEMA_VERSION,
        ',\n  "table": "',
        tn,
        '",\n  "rows": ',
        as_records(tabs[[tn]]),
        "\n}"
      ),
      tpath
    )
    table_index[[tn]] <- aname
  }

  message(
    "  dist/",
    aname,
    ".json  ",
    format(file.size(apath), big.mark = ","),
    " bytes, ",
    length(tabs),
    " tables"
  )
}

# Source hashes let CI prove dist/ was regenerated from the committed sources.
source_files <- c(
  list.files(
    file.path(root, "table-metadata"),
    pattern = "\\.ya?ml$",
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
  artifacts = manifest_artifacts,
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
  length(manifest_artifacts),
  " artifacts)"
)
