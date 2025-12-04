# Processing PAFF IDs that were missed in the initial creation from the Excel spreadsheets

library(tidyverse)
library(arrow)
library(marinegeo.utils)

path_to_files <- paste0(Sys.getenv("repository_filepath"), "marinegeo-reef-life-survey/L1-data/rls-data/PAFF-2025")

target_files <- basename(list.files(path_to_files, recursive = T))

table_id <- "reef-life-survey-data-marinegeo-v1"

df <- marinegeo.utils::db_marinegeo_L2(table_id) %>%
  filter(input_filename %in% target_files) %>%
  collect()

ids_input <- read_csv("taxonomic-ids/marinegeo-taxonomic-ids.csv")

missing_species_ids <- df %>%
  rename(scientific_name = species) %>%
  filter(!is.na(taxonomic_id)) %>%
  count(scientific_name, taxonomic_id) %>%
  anti_join(ids_input)

## Add new IDs ####

ids_out <- ids_input %>%
  bind_rows(missing_species_ids) %>%
  arrange(taxonomic_id)

write_csv(ids_out, "taxonomic-ids/marinegeo-taxonomic-ids.csv")

## Get new classifications ####

classifications_df <- read_csv("taxonomic-classifications/marinegeo_classifications.csv")

needed_classifications <- missing_species_ids %>%
  filter(!taxonomic_id %in% classifications_df$taxonomic_id) %>%
  filter(taxonomic_id > 0)

new_classifications <- api_worms_get_classification(unique(needed_classifications$taxonomic_id))

setdiff(colnames(new_classifications), colnames(classifications_df))

any(classifications_df$taxonomic_id %in% needed_classifications$taxonomic_id)

classifications_out <- classifications_df %>%
  bind_rows(new_classifications) %>%
  arrange(taxonomic_id)

write_csv(classifications_out, "taxonomic-classifications/marinegeo_classifications.csv")
