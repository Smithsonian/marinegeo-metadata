# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

taxa <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv") %>%
  select(parent_id, scientific_id, everything()) %>%
  mutate(parent_id = replace_na(parent_id, "top node")) %>%
  rename(node_name = name)

taxa_tree <- FromDataFrameNetwork(taxa, check = c("check", "no-warn", "no-check"))
print(taxa_tree, "node_name", "rank")

# Build the tree
# Functional groups are sourced from the functional group lookup
macrophytes <- Node$new("FUNCTIONAL:MACROPHYTES", node_name = "Macrophytes", definition = "Aquatic macroscopic plants growing in or near water, including vascular plants and macroalgae")
sav <- macrophytes$AddChild("FUNCTIONAL:SAV", node_name = "Submerged Aquatic Vegetation", definition = "Rooted, vascular plants that grow underwater or just up to the
 water’s surface, often forming large stands or beds.")

nonmarine_sav <- sav$AddChild("FUNCTIONAL:NONMARINESAV", node_name = "Non-marine SAV", definition = "SAV species found primarily in brackish to freshwater habitats.")
nonmarine_sav_ids <- c("APHIA:196239", "APHIA:234029")
lapply(nonmarine_sav_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  nonmarine_sav$AddChildNode(new_node)
})

seagrass <- sav$AddChild("FUNCTIONAL:SEAGRASS", node_name = "Seagrass", definition = "SAV species found in brackish to saline marine environments.")
seagrass_families <- c("APHIA:143768", "APHIA:143751", "APHIA:143769", "APHIA:143770")
lapply(seagrass_families, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  seagrass$AddChildNode(new_node)
})

macroalgae <- macrophytes$AddChild("FUNCTIONAL:MACROALGAE", node_name = "Macroalgae", definition = "Large, multicellular marine algae, also known as seaweed.")
macroalgae_ids <- c("APHIA:801", "APHIA:852", "APHIA:830")
lapply(macroalgae_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  macroalgae$AddChildNode(new_node)
})

macrophytes
print(macrophytes, "node_name")
print(macrophytes, "node_name", "rank")
 
output_network_df <- ToDataFrameNetwork(macrophytes, "node_name", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "macrophytes") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/macrophytes.csv")

# Test out list

sp <- "Zostera marina"

obs_table <- read_csv("taxonomy-and-functional-groups/observation-lookup/marinegeo_observation_ids.csv")

id <- obs_table %>%
  filter(scientific_name == sp) %>%
  pull(scientific_id)

found <- FindNode(macrophytes, id)

parents <- found$path

x <- ToDataFrameNetwork(macrophytes, "node_name", "rank", "definition", direction = "descend")

x %>%
  filter(from %in% parents)