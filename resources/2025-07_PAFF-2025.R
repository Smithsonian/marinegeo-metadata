library(tidyverse)
library(arrow)
library(marinegeo.utils)

path_to_files <- paste0(Sys.getenv("repository_filepath"), "marinegeo-reef-life-survey/L1-data/rls-data/PAFF-2025")

filepaths <- list.files(path_to_files, recursive = T, full.names = T)

df_taxa_by_file <- bind_rows(
  compact(
    lapply(filepaths, function(x){

      df <- marinegeo.utils::utl_mg_load_excel(x, "reef-life-survey-data-marinegeo-v1", "DATA")

      if("species" %in% colnames(df)){

        df %>%
          mutate(filename = x) %>%
          count(species, filename)

      } else {
        NULL
      }

    })
  )
) %>%
  rename(scientific_name = species)

df_all_taxa <- df_taxa_by_file %>%
  select(scientific_name) %>%
  distinct()

already_present_ids <- marinegeo.utils::db_get_taxonomy_by_scientific_name(df_all_taxa$scientific_name)

df_to_resolve <- df_all_taxa %>%
  filter(!scientific_name %in% already_present_ids$scientific_name) %>%
  filter(!is.na(scientific_name))

## Add new IDs ####

# 27 not recognized
# new_ids <- marinegeo.utils::api_worms_get_aphia_id(df_to_resolve$scientific_name)

new_ids_df <- new_ids %>%
  select(taxonomic_id, scientific_name) %>%
  filter(!is.na(taxonomic_id))

ids_input <- read_csv("taxonomic-ids/marinegeo-taxonomic-ids.csv")

ids_out <- ids_input %>%
  bind_rows(new_ids_df) %>%
  arrange(taxonomic_id)

# write_csv(ids_out, "taxonomic-ids/marinegeo-taxonomic-ids.csv")

# Get new classifications

classifications_df <- read_csv("taxonomic-classifications/marinegeo_classifications.csv", guess_max = Inf)

needed_classifications <- new_ids_df %>%
  filter(!taxonomic_id %in% classifications_df$taxonomic_id) %>%
  filter(taxonomic_id > 0)

new_classifications <- api_worms_get_classification(unique(needed_classifications$taxonomic_id))

setdiff(colnames(new_classifications), colnames(classifications_df))

any(classifications_df$taxonomic_id %in% needed_classifications$taxonomic_id)

classifications_out <- classifications_df %>%
  bind_rows(new_classifications) %>%
  arrange(taxonomic_id)

# write_csv(classifications_out, "taxonomic-classifications/marinegeo_classifications.csv")
