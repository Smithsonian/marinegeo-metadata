library(tidyverse)
library(arrow)
library(marinegeo.utils)

df_input <- marinegeo.utils::db_marinegeo_L2("reef-life-survey-data-marinegeo-v1") %>%
  select(species, taxonomic_id) %>%
  filter(!is.na(taxonomic_id)) %>%
  distinct() %>%
  collect() %>%
  rename(scientific_name = species)

already_present_ids <- db_get_taxonomy_by_scientific_name(df_input$scientific_name)

df <- df_input %>%
  filter(!taxonomic_id %in% already_present_ids$taxonomic_id)

## Add new IDs ####

ids_input <- read_csv("taxonomic-ids/marinegeo-taxonomic-ids.csv")

ids_out <- ids_input %>%
  bind_rows(df) %>%
  arrange(taxonomic_id)

# write_csv(ids_out, "taxonomic-ids/marinegeo-taxonomic-ids.csv")

# Get new classifications

needed_classifications <- db_get_taxonomy_by_scientific_name(df_input$scientific_name) %>%
  filter(is.na(level)) %>%
  filter(taxonomic_id > 0)

new_classifications <- api_worms_get_classification(unique(needed_classifications$taxonomic_id))

setdiff(colnames(new_classifications), colnames(needed_classifications))

classifications_input <- read_csv("taxonomic-classifications/marinegeo_classifications.csv", guess_max = Inf)

any(classifications_input$taxonomic_id %in% new_classifications$taxonomic_id)

classifications_out <- classifications_input %>%
  bind_rows(new_classifications) %>%
  arrange(taxonomic_id)

# write_csv(classifications_out, "taxonomic-classifications/marinegeo_classifications.csv")
