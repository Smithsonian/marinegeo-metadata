# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

# Fouling panels are a one-level functional/morpho tree, with some nested taxonomic ranks.

# [1] "Mobile"               "Encrusting bryozoan"  "Anemone"              "Arborescent bryozoan" "Barnacles"            "Amphipod tubes"       "Mussel"
# [8] "Other bivalves"       "Colonial ascidian"    "Other polychaetes"    "Solitary ascidian"    "Kamptozoa"            "Sponge"               "Sabellid"
# [15] "Hydroid"              "Oyster"               "Crepidula"            "Serpulidae"           "Fish eggs"            "Other"                "n/a"
# [22] "Turf algae"           "Vermetid"             "Ser"                  "Terebellid"

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))

fouling_group_assignments_in <- read_csv("R/fouling-panels-assembly/fouling_lookup.csv") %>%
  mutate(scientific_name = trimws(
    str_remove(
      scientific_name, regex("\\s+spp?\\.?\\b.*$",
                             ignore_case = T)
    ))) %>%
  filter(scientific_name != "Elasmopus cf rapax") # dupe of Elasmopus

fouling_group_assignments <- fouling_group_assignments_in %>%
  left_join(obs_df) %>%
  distinct()

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
# Create pathString using display names as identifiers
fouling_group_assignments$pathString <- paste("fouling",
                                              fouling_group_assignments$fg,
                                              fouling_group_assignments$node_name,
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
                     filter(scientific_id != node_id) %>%
                     select(pathString, scientific_id))
# scientific_id is set as an attribute on leaf (species) nodes via as.Node()

# Set scientific_id on functional group (intermediate) nodes
fg_id_lookup <- fouling_group_assignments %>%
  distinct(fg, node_id) %>%
  rename(fg_scientific_id = node_id)

for (i in seq_len(nrow(fg_id_lookup))) {
  fg_node <- FindNode(fouling, fg_id_lookup$fg[i])
  if (!is.null(fg_node)) {
    fg_node$scientific_id <- fg_id_lookup$fg_scientific_id[i]
  }
}

amphipod_tubes <- fouling$AddChild("Amphipod tubes", scientific_id = "FUNCTIONAL:AMPHIPOD_TUBES")
Anemone        <- fouling$AddChild("Anemone", scientific_id = "FUNCTIONAL:ANEMONE")
Barnacles       <- fouling$AddChild("Barnacles", scientific_id = "FUNCTIONAL:BARNACLES")
Fisheggs <- fouling$AddChild("Fish eggs", scientific_id = "FUNCTIONAL:FISH_EGGS")

# Make sure if Turf Algae isn't already in the table:
check <- fouling_group_assignments %>%
  filter(scientific_id != node_id) %>%
  filter(node_id == "FUNCTIONAL:TURF_ALGAE")

if(nrow(check) == 0){
  turf_algae <- fouling$AddChild("Turf Algae", scientific_id = "FUNCTIONAL:TURF_ALGAE")
}

print(fouling, "scientific_id", limit = 20)

output_network_df <- ToDataFrameNetwork(fouling, "scientific_id", direction = "descend")

output_network_df %>%
  mutate(tree_name = "fouling",
         rank = NA,
         definition = NA) %>%
  select(from, to, scientific_id, rank, definition, tree_name) %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/fouling.csv")
