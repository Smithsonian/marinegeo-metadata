# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

# Vegetation tree includes major categories of "Algae" and "SAV", with sub-children "microalgae", "macroalgae", and "Seagrass"

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

taxa_raw <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv") 

# taxon names are used as node IDs, with scientific IDs as an attribute. 
# Therefore there cannot be any duplicate taxon names
taxa_dupe_names <- taxa_raw %>%
  count(name) %>% 
  filter(n > 1) %>%
  pull(name)

taxa <- taxa_raw %>%
  mutate(name = case_when(
    name %in% taxa_dupe_names ~ paste0(name, "-", id),
    T ~ name
  ))

# Build a lookup to map parent scientific_id -> parent name
parent_names <- taxa %>%
  select(scientific_id, name) %>%
  rename(parent_id = scientific_id,
         parent_name = name)

# Use name as node identifier, scientific_id as attribute
taxa_network <- taxa %>%
  left_join(parent_names, by = c("parent_id")) %>%
  mutate(parent_name = replace_na(parent_name, "top node")) %>%
  rename(child_name = name) %>%
  select(parent_name, child_name, scientific_id, rank)

taxa_tree <- FromDataFrameNetwork(taxa_network, check = "no-warn")
print(taxa_tree, "scientific_id", "rank")

# Build the tree
# Functional groups are sourced from the functional group lookup
vegetation <- Node$new("Vegetation", scientific_id = "FUNCTIONAL:VEGETATION", definition = "Aquatic micro- and macroscopic photosynthetic organisms growing in or near water")

# Seagrass, defined inclusively (Seagrass = SAV, here).
sav <- vegetation$AddChild("Seagrass", scientific_id = "FUNCTIONAL:SAV", definition = "Rooted, vascular plants that grow underwater or just up to the
 water's surface, often forming large stands or beds.")

nonmarine_sav <- sav$AddChild("Non-marine SAV", scientific_id = "FUNCTIONAL:NONMARINESAV", definition = "SAV species found primarily in brackish to freshwater habitats.")
nonmarine_sav_ids <- c("Potamogetonaceae", "Ruppiaceae")
lapply(nonmarine_sav_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  nonmarine_sav$AddChildNode(new_node)
})

seagrass <- sav$AddChild("Marine Seagrass", scientific_id = "FUNCTIONAL:SEAGRASS", definition = "SAV species found in brackish to saline marine environments.")
seagrass_families <- c("Cymodoceaceae", "Hydrocharitaceae", "Posidoniaceae", "Zosteraceae")
lapply(seagrass_families, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  seagrass$AddChildNode(new_node)
})

algae <- vegetation$AddChild("Algae", scientific_id = "FUNCTIONAL:ALGAE", definition = "Plantlike photosynthetic organisms, from single-celled to large, multicellular marine algae.")

# Macroalgae
macroalgae <- algae$AddChild("Macroalgae", scientific_id = "FUNCTIONAL:MACROALGAE")
macroalgae_ids <- c("Chlorophyta", "Rhodophyta", "Phaeophyceae")
lapply(macroalgae_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  macroalgae$AddChildNode(new_node)
})

# Other algae: Cyanobacteria (including Dapis pleousa, Lyngbya sp)
algae_ids <- c("Cyanobacteria")
lapply(algae_ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  algae$AddChildNode(new_node)
})

vegetation
print(vegetation, "scientific_id")
print(vegetation, "scientific_id", "rank")

output_network_df <- ToDataFrameNetwork(vegetation, "scientific_id", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "vegetation") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/vegetation.csv")
