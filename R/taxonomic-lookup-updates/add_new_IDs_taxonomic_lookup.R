library(tidyverse)
library(taxize)

obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))
taxa_df <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv")

lsid_stem <- "urn:lsid:marinespecies.org:taxname:"

missing_taxa <- obs_df %>%
  filter(!scientific_id %in% taxa_df$scientific_id) %>%
  filter(str_starts(scientific_id, lsid_stem))

missing_taxa

ids <- as.numeric(gsub(lsid_stem, "", missing_taxa$scientific_id))
ids

out <- classification(ids, db="worms")
out

results <- bind_rows(
  lapply(out, function(i){
    i %>%
      mutate(parent_id = case_when(
        is.na(lag(id, n = 1)) ~ NA,
        T ~ paste0(lsid_stem, lag(id, n = 1))
      ))
  })
) %>%
  distinct() %>%
  mutate(scientific_id = paste0(lsid_stem, id)) %>%
  select(scientific_id, everything())

taxa_df_updated <- bind_rows(
  results, taxa_df
) %>%
  arrange(id) %>%
  distinct()

write_csv(taxa_df_updated, "taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv")
