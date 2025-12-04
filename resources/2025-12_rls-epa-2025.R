library(tidyverse)
library(readxl)
library(marinegeo.utils)

files <- list.files(
  paste0(Sys.getenv("repository_filepath"), "marinegeo-reef-life-survey/L1-data/rls-data/EPA-2025/"),
  recursive = T, full.names = T
)

table_out <- 'reef-life-survey-data-marinegeo-v1'

species <- lapply(files, function(x){
  # Load data
  df <- marinegeo.utils::utl_mg_load_excel(x, table_out, 'DATA') %>%
    count(species) %>%
    select(-n)

}) %>%
  bind_rows() %>%
  distinct()

review <- marinegeo.utils::db_get_taxonomy_by_scientific_name(species$species)

species_to_id <- species %>%
  filter(!species %in% review$scientific_name) %>%
  filter(!str_starts(species, "Debris"))

updated_ids <- marinegeo.utils::api_worms_get_aphia_id(species_to_id$species)

## Add new IDs ####
new_ids <- updated_ids %>%
  select(-name_to_evaluate) %>%
  filter(!is.na(taxonomic_id)) %>%
  distinct()

ids_input <- read_csv("taxonomic-ids/marinegeo-taxonomic-ids.csv")

ids_out <- ids_input %>%
  #select(-n) %>%
  #filter(!is.na(taxonomic_id)) %>%
  bind_rows(new_ids) %>%
  arrange(taxonomic_id)

write_csv(ids_out, "taxonomic-ids/marinegeo-taxonomic-ids.csv")

# Get new classifications

classifications_input <- read_csv("taxonomic-classifications/marinegeo_classifications.csv")

needed_classifications <- new_ids %>%
  filter(!taxonomic_id %in% classifications_input$taxonomic_id)

new_classifications <- api_worms_get_classification(unique(needed_classifications$taxonomic_id))

setdiff(colnames(new_classifications), colnames(needed_classifications))

any(classifications_input$taxonomic_id %in% new_classifications$taxonomic_id)

classifications_out <- classifications_input %>%
  bind_rows(new_classifications) %>%
  arrange(taxonomic_id)

classifications_out %>%
  count(taxonomic_id) %>%
  filter(n > 1)

write_csv(classifications_out, "taxonomic-classifications/marinegeo_classifications.csv")

