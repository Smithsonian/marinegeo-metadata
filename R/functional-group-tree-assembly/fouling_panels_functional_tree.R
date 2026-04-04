# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

# Fouling panels are a one-level functional/morpho tree, with some nested taxonomic ranks.

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))
taxa <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv") %>%
  select(parent_id, scientific_id, everything()) %>%
  mutate(parent_id = replace_na(parent_id, "top node")) %>%
  rename(node_name = name)

taxa_tree <- FromDataFrameNetwork(taxa, check = c("check", "no-warn", "no-check"))
print(taxa_tree, "node_name", "rank")

fouling_group_assignments_in <- read_csv("R/fouling-panels-assembly/fouling_lookup.csv")

fouling_group_assignments <- fouling_group_assignments_in %>%
  left_join(obs_df) 

# Evaluate NA IDs
# Make sure Turf Algae is manually added
fouling_group_assignments %>%
  filter(is.na(scientific_id)) 

# Things to watch out for:
# 1. node name != node ID - this happens below when the name is also the group (e.g., FUNCTIONAL:FISH_EGGS)
# 2. there are IDs > 1 due to different names. 

# Evaluate dupes - if all can be condensed by using resolver name instead of scientific_name, 
# you're good to advance in script
dupes <- fouling_group_assignments %>% count(scientific_id) %>% filter(n>1) %>% pull(scientific_id)
fouling_group_assignments %>%
  filter(!is.na(scientific_id)) %>%
  filter(scientific_id %in% dupes)

fouling_group_assignments <- fouling_group_assignments %>%
  filter(!is.na(scientific_id)) %>%
  mutate(scientific_name = case_when(
    scientific_name %in% dupes ~ resolver,
    T ~ scientific_name
  )) %>%
  select(scientific_id, fg, scientific_name) %>%
  mutate(node_id = paste0(
    "FUNCTIONAL:",
    toupper(gsub(" ", "_", fg))
  )) %>%
  rename(node_name = scientific_name)

# Build the tree
# Create pathString defining relationships
fouling_group_assignments$pathString <- paste("fouling", 
                                              fouling_group_assignments$node_id, 
                                              fouling_group_assignments$scientific_id, 
                                              sep = "/")

# You cannot have Scientific IDs, which reflect functional IDs, nested under itself
# For instance, the df has a row FUNCTIONAL:FISH_EGGS - FUNCTIONAL:FISH_EGGS
# These will need to be added manually

solo_ids <- fouling_group_assignments %>%
  count(scientific_id) %>%
  filter(n == 1) %>%
  pull(scientific_id)

solo_fgs <- fouling_group_assignments %>%
  filter(scientific_id == node_id,
         scientific_id %in% solo_ids)

fouling <- as.Node(fouling_group_assignments %>%
                     filter(scientific_id != node_id))

amphipod_tubes <- fouling$AddChild("FUNCTIONAL:AMPHIPOD_TUBES", node_name = "Amphipod tubes")
Anemone        <- fouling$AddChild("FUNCTIONAL:ANEMONE", node_name = "Anemone")
Barnacles       <- fouling$AddChild("FUNCTIONAL:BARNACLES", node_name = "Barnacles")
Fisheggs <- fouling$AddChild("FUNCTIONAL:FISH_EGGS", node_name = "Fish eggs")

# Make sure if Turf Algae isn't already in the table: 
check <- fouling_group_assignments %>%
  filter(scientific_id != node_id) %>%
  filter(node_id == "FUNCTIONAL:TURF_ALGAE")

if(nrow(check) == 0){
  turf_algae <- fouling$AddChild("FUNCTIONAL:TURF_ALGAE", node_name = "Turf Algae")
}

print(fouling, "node_name", limit = 20)

output_network_df <- ToDataFrameNetwork(fouling, "node_name", direction = "descend")
head(output_network_df)

# Add node name for groups
group_df <- fouling_group_assignments_in %>%
  count(fg) %>%
  mutate(from = paste0(
    "FUNCTIONAL:",
    toupper(gsub(" ", "_", fg))
  )) %>%
  select(-n) %>%
  rename(new_node_name = fg)
  

output_network_df %>%
  mutate(tree_name = "fouling",
        rank = NA,
      definition = NA) %>%
  left_join(group_df) %>%
  mutate(node_name = case_when(
    is.na(node_name) ~ new_node_name,
    T ~ node_name
  )) %>%
  select(from, to, node_name, rank, definition, tree_name) %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/fouling.csv")
