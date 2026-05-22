library(tidyverse)

df_obs <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))

df_obs_updated <- df_obs %>%
  mutate(scientific_name_updated = trimws(
    str_remove(
      scientific_name, regex("\\s+spp?\\.?\\b.*$",
                             ignore_case = T)
    ))) %>%
  select(scientific_name_updated, scientific_id) %>%
  rename(scientific_name = scientific_name_updated) %>%
  distinct() %>%
  mutate(scientific_id = case_when(
    str_starts(scientific_id, "APHIA:") ~ gsub(
      "APHIA:", "urn:lsid:marinespecies.org:taxname:", scientific_id),
    T ~ scientific_id
  )) %>%
  arrange(scientific_id)

write_csv(df_obs_updated, "taxonomy-and-functional-groups/observation-lookup/marinegeo_observation_ids.csv")

df_taxa <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv")

df_taxa_updated <- df_taxa %>%
  mutate(scientific_id = case_when(
    str_starts(scientific_id, "APHIA:") ~ gsub(
      "APHIA:", "urn:lsid:marinespecies.org:taxname:", scientific_id),
    T ~ scientific_id
  )) %>%
  mutate(parent_id = case_when(
    str_starts(parent_id, "APHIA:") ~ gsub(
      "APHIA:", "urn:lsid:marinespecies.org:taxname:", parent_id),
    T ~ parent_id
  )) %>%
  arrange(id)

write_csv(df_taxa_updated, "taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv")
