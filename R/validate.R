library(marinegeo.utils)
library(readr, quietly = TRUE, warn.conflicts = FALSE)

read_table <- function(table_path, label) {
  tryCatch(
    readr::read_csv(list.files(table_path, full.names = TRUE),
                    show_col_types = F),
    error = function(e) {
      message(label, ": error reading CSV — ", conditionMessage(e))
      NULL
    }
  )
}

observation_lookup <- read_table(
  "./taxonomy-and-functional-groups/observation-lookup/",
  "Observation Lookup Table"
)
taxonomic_lookup <- read_table(
  "./taxonomy-and-functional-groups/taxonomic-lookup/",
  "Taxonomic Lookup Table"
)
functional_group_lookup <- read_table(
  "./taxonomy-and-functional-groups/functional-group-lookup/",
  "Functional Group/Morphological Lookup Table"
)

site_lookup <- read_table(
  "./sites-and-partners/site-names/",
  "MarineGEO Site Lookup Table"
)
partner_lookup <- read_table(
  "./sites-and-partners/partner-codes/",
  "MarineGEO Partner Lookup Table"
)



report_qc <- function(data, table_id, label) {
  if (is.null(data)) return(invisible(NULL))
  result <- utl_qc_summarize(qc_run(data, table_id = table_id), type = "failures")
  if (nrow(result$failures) == 0) {
    message(label, ": no failures")
  } else {
    message(label, ":")
    print(result$failures)
  }
}

report_qc(observation_lookup, "observation_lookup", "Observation Lookup Table")
cat("----")
report_qc(taxonomic_lookup, "taxonomic_lookup", "Taxonomic Lookup Table")
cat("----")
report_qc(functional_group_lookup, "functional_group_lookup", "Functional Group/Morphological Lookup Table")
cat("----")
report_qc(site_lookup, "site_lookup", "MarineGEO Site Lookup Table")
cat("----")
report_qc(partner_lookup, "partner_lookup", "MarineGEO Partner Lookup Table")
