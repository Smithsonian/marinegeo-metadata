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
fouling_group_assignments %>%
  filter(is.na(scientific_id)) 

fouling_group_assignments <- fouling_group_assignments %>%
  filter(!is.na(scientific_id)) 

# Build the tree

# Because it's one-level, a for loop builds the list
# But future changes might require a manual construction

groups <- unique(fouling_group_assignments$fg)
groups

fouling <- Node$new("FUNCTIONAL:FOULING", node_name = "Fouling")

for(group in groups){
  node_id <- paste0(
    "FUNCTIONAL:",
    toupper(gsub(" ", "_", group))
  )

  new_node <- fouling$AddChild(node_id, node_name = group)

  children <- fouling_group_assignments %>%
    filter(group == !!group) %>%
    select(scientific_name, scientific_id)

  for(i in 1:nrow(children)){
    input_name <- children[i,1]
    input_id <- children[i,2]

    new_node$AddChild(input_id, node_name = input_name)
  }
}

output_network_df <- ToDataFrameNetwork(fouling, "node_name", direction = "descend")

output_network_df %>%
  mutate(tree_name = "fouling") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/fouling.csv")
