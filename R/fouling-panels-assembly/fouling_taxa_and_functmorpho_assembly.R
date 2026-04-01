# Taxonomic and Functional group assembly script
# Based on initial script created by Dean for USA-IRL
# Can be added to with additional species from additional sites

library(tidyverse)
library(taxize)

# Define Sci Name values with an associated functional group/morho
# Additional column with clean formatting for resolving Aphia ID
df_in <- read_csv("R/fouling-panels-assembly/fouling_lookup.csv")

# Load existing observation and taxa lookup tables
obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))
taxa_df <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv") 

## Examine Function Groups ##

# fgs to ask Dean about : Serpulidae, Crepidula
# We only need to add the functional groups that are themselves added as Sci Names to the obs table
# Everything else will be assigned only to the functional group tree. 

new_fg <- df_in %>%
  count(fg) %>%
  filter(fg != "n/a") %>%
  mutate(scientific_id = paste0("FUNCTIONAL:", toupper(gsub(" ", "_", fg)))) %>%
  rename(scientific_name = fg) %>%
  select(-n)

df_in %>%
  filter(scientific_name %in% new_fg$scientific_name)

# Ignore cases where sci name is likely a Family or genus, might not be FG
# Output piece ready to be sent to observation lookup table
new_fg_to_obs <- new_fg %>%
  filter(!scientific_name %in% c("Serpulidae", "Crepidula")) %>%
  filter(scientific_name %in% df_in$scientific_name) %>%
  filter(!scientific_id %in% obs_df$scientific_id)

## Sci Names for Observation Table ##
# Check for names with no corresponding ID in existing observation table
needs_id_resolved <- df_in %>%
  filter(!scientific_name %in% unique(obs_df$scientific_name), 
         !scientific_name %in% new_fg$scientific_name, !is.na(resolver)
  )

# Run taxize package to get IDs
ids <- unique(needs_id_resolved$resolver)
new_ids <- taxize::get_wormsid_(ids, accepted = TRUE, fuzzy = FALSE)

new_ids_df <- bind_rows(
  lapply(names(new_ids), function(i){
    if(!is.null(new_ids[[i]])){
      new_ids[[i]] %>%
        mutate(resolver = i) %>%
        select(-authority)
    }
  })
) %>%
  mutate(scientific_id = paste0("APHIA:", AphiaID)) %>%
  select(scientific_id, resolver) %>%
  distinct()

# Output piece ready to be sent to observation lookup table
obs_new_ids <- left_join(
  needs_id_resolved, new_ids_df
) %>%
  filter(!is.na(scientific_id)) %>%
  select(scientific_name, scientific_id) %>%
  distinct()

# Missing IDs (unresolved)
obs_missing_ids <- left_join(
  needs_id_resolved, new_ids_df
) %>%
  filter(is.na(scientific_id)) %>%
  #select(scientific_name, scientific_id) %>%
  distinct() 

# Try a fuzzy search (not very successful on first batch): 
# You can load "R/fouling-panels-assembly/missing_ids_fouling.csv" ahead of time
# to avoid rerunning this if you've already tried to resolve certain IDs
missing_ids <- unique(obs_missing_ids$resolver)
missing_ids_fuzzy <- taxize::get_wormsid_(missing_ids, accepted = TRUE, fuzzy = TRUE)

# Recommend updating fouling_lookup.csv with the correct names for the resolver, could also manually add
# Meanwhile, unresolved names can get a "UNDEFINED:xyz" placeholder ID
# write_csv(obs_missing_ids, "R/fouling-panels-assembly/missing_ids_fouling.csv")

# Output piece ready to be sent to observation lookup table
obs_undefined <- obs_missing_ids %>%
  mutate(scientific_id = paste0("UNDEFINED:",
                                toupper(gsub(" ", "_", scientific_name)))) %>%
  select(scientific_name, scientific_id)

## Write out observation lookup sub-table ##

# Check for duplicates 
bind_rows(
  obs_df, 
  obs_new_ids, 
  new_fg_to_obs, 
  obs_undefined
) %>%
  count(scientific_name) %>%
  filter(n > 1)

fouling_obs_ids_in <- read_csv("taxonomy-and-functional-groups/observation-lookup/fouling_panel_observation_ids.csv")

fouling_obs_ids <- bind_rows(
  fouling_obs_ids_in,
  #obs_undefined, 
  #new_fg_to_obs, 
  obs_new_ids
)

write_csv(fouling_obs_ids, "taxonomy-and-functional-groups/observation-lookup/fouling_panel_observation_ids.csv")

## Get classifications for any new species ##
# Use script at "R/taxonomic-lookup-updates/add_new_IDs_taxonomic_lookup.R"
