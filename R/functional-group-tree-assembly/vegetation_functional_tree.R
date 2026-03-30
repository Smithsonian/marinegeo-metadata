# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

# Vegetation tree includes major categories of "Algae" and "SAV", with sub-children "microalgae", "macroalgae", and "Seagrass"

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
vegetation <- Node$new("FUNCTIONAL:VEGETATION", node_name = "Vegetation", definition = "Aquatic micro- and macroscopic photosynthetic organisms growing in or near water")

# Seagrass, defined inclusively (Seagrass = SAV, here). 
sav <- vegetation$AddChild("FUNCTIONAL:SAV", node_name = "Seagrass", definition = "Rooted, vascular plants that grow underwater or just up to the
 water’s surface, often forming large stands or beds.")

nonmarine_sav <- sav$AddChild("FUNCTIONAL:NONMARINESAV", node_name = "Non-marine SAV", definition = "SAV species found primarily in brackish to freshwater habitats.")
nonmarine_sav_ids <- c("APHIA:196239", "APHIA:234029")
lapply(nonmarine_sav_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  nonmarine_sav$AddChildNode(new_node)
})

seagrass <- sav$AddChild("FUNCTIONAL:SEAGRASS", node_name = "Marine Seagrass", definition = "SAV species found in brackish to saline marine environments.")
seagrass_families <- c("APHIA:143768", "APHIA:143751", "APHIA:143769", "APHIA:143770")
lapply(seagrass_families, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  seagrass$AddChildNode(new_node)
})

# Splitting Algae into functional groups will wait

algae <- vegetation$AddChild("FUNCTIONAL:ALGAE", node_name = "Algae", definition = "Plantlike photosynthetic organisms, from single-celled to large, multicellular marine algae.")

# Macroalgae
macroalgae <- algae$AddChild("FUNCTIONAL:MACROALGAE", node_name = "Macroalgae")
macroalgae_ids <- c("APHIA:801", "APHIA:852", "APHIA:830")
lapply(macroalgae_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  macroalgae$AddChildNode(new_node)
})

# Other algae: Cyanobacteria (including Dapis pleousa, Lyngbya sp)
algae_ids <- c("APHIA:146537")
lapply(algae_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  algae$AddChildNode(new_node)
})

vegetation
print(vegetation, "node_name")
print(vegetation, "node_name", "rank")
 
output_network_df <- ToDataFrameNetwork(vegetation, "node_name", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "vegetation") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/vegetation.csv")

# Test out list

sp <- "Zostera marina"

obs_table <- read_csv("taxonomy-and-functional-groups/observation-lookup/marinegeo_observation_ids.csv")

id <- obs_table %>%
  filter(scientific_name == sp) %>%
  pull(scientific_id)

found <- FindNode(vegetation, id)

parents <- found$path

x <- ToDataFrameNetwork(vegetation, "node_name", "rank", "definition", direction = "descend")

x %>%
  filter(from %in% parents)