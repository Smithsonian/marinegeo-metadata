# One-shot conversion of table-metadata/ from CSV to per-protocol YAML.

suppressPackageStartupMessages({
  library(readr)
})

root <- normalizePath(".", mustWork = TRUE)
tm <- file.path(root, "table-metadata")
stopifnot(dir.exists(tm))

read_dir <- function(sub) {
  files <- sort(list.files(file.path(tm, sub), pattern = "\\.csv$", full.names = TRUE))
  stopifnot(length(files) > 0)
  readr::read_csv(files, show_col_types = FALSE, progress = FALSE)
}

struct <- read_dir("data-structure")
vocab <- read_dir("categorical-values")
ranges <- read_dir("numeric-ranges")
conds <- read_dir("qc-conditions")
aggs <- read_dir("aggregate-rules")
cross <- read_dir("cross-table-rules")

# Source file -> output YAML basename. Names are chosen so the sorted order of
# the YAML files matches the sorted order of the CSVs they replace, which is what
# preserves database_structure row order through the migration.
out_names <- c(
  "darwin-core_data-structure.csv" = "darwin-core.yaml",
  "fouling-panels_data-structure.csv" = "fouling-panels.yaml",
  "marinegeo_metadata_tables.csv" = "marinegeo-metadata-tables.yaml",
  "oyster-experiment-2025_data-structure.csv" = "oyster-experiment-2025.yaml",
  "oyster-reef-monitoring_data-structure.csv" = "oyster-reef-monitoring.yaml",
  "reef-life-survey_data-structure.csv" = "reef-life-survey.yaml",
  "seagrass-monitoring_data-structure.csv" = "seagrass-monitoring.yaml"
)

ds_files <- sort(list.files(file.path(tm, "data-structure"), pattern = "\\.csv$"))
stopifnot(setequal(ds_files, names(out_names)))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

nz <- function(x) !is.na(x) & nzchar(as.character(x))

# Whole numbers emit as integers for readability; as.yaml would otherwise write
# every numeric as "1.0".
num <- function(x) {
  x <- as.numeric(x)
  if (!is.na(x) && x == round(x) && abs(x) < 2^31) as.integer(x) else x
}

split_pipe <- function(x) {
  if (is.na(x)) {
    return(character(0))
  }
  parts <- trimws(strsplit(as.character(x), "|", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

# A `|`-delimited metadata list becomes a scalar when it holds one value and a
# sequence when it holds several.
pipe_value <- function(x) {
  parts <- split_pipe(x)
  if (length(parts) == 1L) parts[[1]] else as.list(parts)
}

na_operators <- c("is_na", "not_na")

# Build a `when:` block from the qc_conditions rows sharing one condition_id.
# `label` carries the original id through, so condition ids -- which surface in
# user-facing QC messages -- do not change in the migration.
when_block <- function(cid, with_table = FALSE) {
  rows <- conds[conds$condition_id == cid, , drop = FALSE]
  stopifnot(nrow(rows) > 0)

  terms <- lapply(seq_len(nrow(rows)), function(i) {
    op <- rows$operator[[i]]
    term <- list(column = rows$column_name[[i]])
    term[[op]] <- if (op %in% na_operators) TRUE else pipe_value(rows$value[[i]])
    term
  })

  out <- list(label = cid)
  if (with_table) {
    out$table <- rows$table_id[[1]]
  }
  if (nz(rows$description[[1]])) {
    out$description <- rows$description[[1]]
  }
  out$all <- terms
  out
}

# ---------------------------------------------------------------------------
# Orphan guard
# ---------------------------------------------------------------------------
#
# A vocabulary or range row keyed to a (table_id, column_name) that does not
# exist in data-structure has no home in the nested format: rules hang off the
# column they constrain. Such a row is already dead config today -- the checks
# filter rules to columns present in the submitted data, so it never fires --
# but dropping it silently during conversion would be exactly the invisible
# behaviour change this migration exists to eliminate. So: fail loudly.

known_cols <- paste(struct$table_id, struct$column_name, sep = " :: ")

orphans <- function(d, label) {
  wanted <- paste(d$table_id, d$column_name, sep = " :: ")
  bad <- unique(wanted[!wanted %in% known_cols])
  if (length(bad) > 0) {
    stop(
      "\n", label, " reference column(s) absent from data-structure:\n",
      paste0("  - ", bad, collapse = "\n"),
      "\n\nThese rows cannot be expressed in the nested format and would be",
      "\nsilently dropped. Fix the source CSV (correct the table_id, or add",
      "\nthe column to data-structure, or delete the row), then re-run.",
      call. = FALSE
    )
  }
}

orphans(vocab, "categorical-values rows")
orphans(ranges, "numeric-ranges rows")

# Conditions actually pointed at by a rule. Everything else is emitted in the
# file-level `conditions:` block so the migration stays lossless.
referenced <- unique(c(
  ranges$condition_id,
  vocab$condition_id,
  aggs$condition_id,
  cross$left_condition_id,
  cross$right_condition_id
))
referenced <- as.character(referenced[nz(referenced)])

# ---------------------------------------------------------------------------
# Emit one document per protocol file
# ---------------------------------------------------------------------------

for (src in ds_files) {
  ds <- struct[struct$protocol %in% unique(struct$protocol), , drop = FALSE]
  # Re-read the single file so table and column order match it exactly.
  ds <- readr::read_csv(
    file.path(tm, "data-structure", src),
    show_col_types = FALSE,
    progress = FALSE
  )

  file_protocol <- names(sort(table(ds$protocol), decreasing = TRUE))[[1]]
  file_level <- as.numeric(names(sort(table(ds$level), decreasing = TRUE))[[1]])

  table_ids <- unique(ds$table_id)
  tables <- list()

  for (tid in table_ids) {
    rows <- ds[ds$table_id == tid, , drop = FALSE]

    node <- list(table_id = tid)
    if (rows$protocol[[1]] != file_protocol) {
      node$protocol <- rows$protocol[[1]]
    }
    if (rows$level[[1]] != file_level) {
      node$level <- num(rows$level[[1]])
    }

    node$columns <- lapply(seq_len(nrow(rows)), function(i) {
      cname <- rows$column_name[[i]]
      col <- list(name = cname, type = rows$data_type[[i]])

      # The source CSVs predate the rename: their `enforce` is today's `fail`.
      if (nz(rows$missing_values[[i]])) {
        col$na_values <- switch(
          rows$missing_values[[i]],
          enforce = "fail",
          rows$missing_values[[i]]
        )
      }
      if (isTRUE(rows$uuid_identity[[i]])) {
        col$uuid_identity <- TRUE
      }

      # Controlled vocabulary: one entry per condition group.
      v <- vocab[vocab$table_id == tid & vocab$column_name == cname, , drop = FALSE]
      if (nrow(v) > 0) {
        groups <- unique(ifelse(nz(v$condition_id), as.character(v$condition_id), NA))
        entries <- lapply(groups, function(g) {
          sel <- if (is.na(g)) !nz(v$condition_id) else v$condition_id == g
          values <- as.list(as.character(v$value[sel]))
          if (is.na(g)) values else list(when = when_block(g), values = values)
        })
        # The common case -- a single unconditional list -- emits as a bare
        # sequence of values rather than a one-element wrapper.
        col$one_of <- if (length(entries) == 1L && is.na(groups[[1]])) {
          entries[[1]]
        } else {
          entries
        }
      }

      # Numeric ranges: `range_type: ~` is emitted explicitly for rows that have
      # none, so the 12 inert rows in the CSVs survive the round trip.
      r <- ranges[ranges$table_id == tid & ranges$column_name == cname, , drop = FALSE]
      if (nrow(r) > 0) {
        entries <- lapply(seq_len(nrow(r)), function(j) {
          e <- list()
          e["range_type"] <- if (nz(r$range_type[[j]])) {
            list(r$range_type[[j]])
          } else {
            list(NULL)
          }
          for (b in c("max_fail", "min_fail", "max_warn", "min_warn")) {
            if (!is.na(r[[b]][[j]])) {
              e[[b]] <- num(r[[b]][[j]])
            }
          }
          if (nz(r$condition_id[[j]])) {
            e$when <- when_block(as.character(r$condition_id[[j]]))
          }
          e
        })
        col$numeric_range <- if (length(entries) == 1L) entries[[1]] else entries
      }

      col
    })

    # Table-scoped checks.
    checks <- list()

    a <- aggs[aggs$table_id == tid, , drop = FALSE]
    if (nrow(a) > 0) {
      checks$aggregate <- lapply(seq_len(nrow(a)), function(j) {
        rule <- list(
          rule_id = a$rule_id[[j]],
          group_by = as.list(split_pipe(a$group_columns[[j]])),
          value = a$value_column[[j]]
        )
        rule[["function"]] <- a$aggregate_function[[j]]
        rule$comparison <- a$comparison[[j]]
        if (nz(a$target_column[[j]])) {
          rule$target_column <- a$target_column[[j]]
        }
        if (!is.na(a$target_value[[j]])) {
          rule$target_value <- num(a$target_value[[j]])
        }
        if (!is.na(a$tolerance[[j]])) {
          rule$tolerance <- num(a$tolerance[[j]])
        }
        if (nz(a$severity[[j]])) {
          rule$severity <- a$severity[[j]]
        }
        if (nz(a$description[[j]])) {
          rule$description <- a$description[[j]]
        }
        if (nz(a$condition_id[[j]])) {
          rule$when <- when_block(as.character(a$condition_id[[j]]))
        }
        rule
      })
    }

    # Cross-table rules are hosted on the LEFT table: the relation is
    # directional and the left table is where failures are reported.
    x <- cross[cross$left_table_id == tid, , drop = FALSE]
    if (nrow(x) > 0) {
      checks$cross_table <- lapply(seq_len(nrow(x)), function(j) {
        left <- split_pipe(x$left_columns[[j]])
        right <- split_pipe(x$right_columns[[j]])
        stopifnot(length(left) == length(right))

        rule <- list(
          rule_id = x$rule_id[[j]],
          relation = x$relation_type[[j]],
          right_table = x$right_table_id[[j]]
        )
        grp <- split_pipe(x$group_columns[[j]])
        if (length(grp) > 0) {
          rule$group_by <- as.list(grp)
        }
        # Named pairs rather than two positionally-aligned lists, so a
        # length mismatch is not expressible.
        rule$on <- lapply(seq_along(left), function(k) {
          list(left = left[[k]], right = right[[k]])
        })
        if (nz(x$severity[[j]])) {
          rule$severity <- x$severity[[j]]
        }
        if (nz(x$description[[j]])) {
          rule$description <- x$description[[j]]
        }
        if (nz(x$left_condition_id[[j]])) {
          rule$when_left <- when_block(as.character(x$left_condition_id[[j]]))
        }
        if (nz(x$right_condition_id[[j]])) {
          rule$when_right <- when_block(as.character(x$right_condition_id[[j]]))
        }
        rule
      })
    }

    if (length(checks) > 0) {
      node$checks <- checks
    }
    tables[[length(tables) + 1L]] <- node
  }

  doc <- list(schema_version = 2L, protocol = file_protocol, level = num(file_level))
  doc$tables <- tables

  # Unreferenced conditions whose table belongs to this file.
  mine <- conds$condition_id[conds$table_id %in% table_ids]
  orphans <- unique(as.character(mine[!mine %in% referenced]))
  if (length(orphans) > 0) {
    doc$conditions <- lapply(orphans, when_block, with_table = TRUE)
  }

  out <- file.path(tm, out_names[[src]])
  writeLines(
    c(
      paste0("# ", out_names[[src]], " -- MarineGEO table metadata (", file_protocol, ")"),
      "#",
      "# Authoring format. The flat registry tables the QC engine consumes are",
      "# derived from this file; see R/convert-table-metadata-to-yaml.R.",
      "#",
      "# Quote any value YAML 1.1 would otherwise read as a number or a boolean:",
      "# column names like \"137.5\", vocabulary values like \"0.1\" or \"TRUE\",",
      "# and comparison operators like \">=\".",
      "",
      yaml::as.yaml(doc, handlers = list(logical = yaml::verbatim_logical))
    ),
    out
  )
  message("wrote ", out_names[[src]], " (", length(tables), " tables, ", nrow(ds), " columns)")
}

message("done")
