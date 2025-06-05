
library(tidyverse)
library(marinegeo.utils)

path_to_data <- paste0(
  Sys.getenv("onedrive_resources"),
  "misc/coralnet-label-migration/coralnet_labelset_with_aphia.csv"
)

df_input <- read_csv(path_to_data) %>%
  select(scientific_name, taxonomic_id) %>%
  filter(!is.na(taxonomic_id)) %>%
  distinct()

already_present_ids <- db_get_taxonomy_by_scientific_name(df_input$scientific_name)

df <- df_input %>%
  filter(!taxonomic_id %in% already_present_ids$taxonomic_id)

#source("resources/db_add_new_taxonomy.R")
#db_add_new_taxonomic_ids(df)

ids_input <- read_csv("taxonomic-ids/marinegeo-taxonomic-ids.csv")

ids_out <- ids_input %>%
  bind_rows(df) %>%
  arrange(taxonomic_id)

write_csv(ids_out, "taxonomic-ids/marinegeo-taxonomic-ids.csv")

# Get new classifications

