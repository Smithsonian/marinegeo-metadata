library(marinegeo.utils)
library(tidyverse)

cover_db <- "seagrass-cover-monitoring-v1"
cover_sp <- marinegeo.utils::db_marinegeo_L2(cover_db) %>%
  count(scientific_name, taxonomic_id) %>%
  collect()

species <- marinegeo.utils::db_get_taxonomy_by_taxonomic_id(unique(cover_sp$taxonomic_id)) %>%
  filter(kingdom != "Animalia" | is.na(kingdom)) %>%
  select(taxonomic_id, kingdom, phylum_division, class) %>%
  mutate(group = case_when(
    # Algae
    phylum_division == "Chlorophyta"  ~ "Green Algae",
    phylum_division == "Rhodophyta" ~ "Red Algae",


    class == "Magnoliopsida" ~ "Seagrass",
     T ~ "Algae"
  ))

