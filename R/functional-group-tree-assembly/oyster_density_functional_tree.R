# Functional group tree to support Oyster Height / Count tables
# Nest data into three categories: 
# Oysters (Measure and count)
# Non-oyster bivalves and gastropods (Measure and count)
# All other non-sessile invertebrates (Presence)

library(data.tree)
library(tidyverse)

taxa_df <- read_csv(list.files("taxonomy-and-functional-groups/taxonomic-lookup/", full.names = T))

source("R/taxonomic-lookup-updates/taxonomy_helpers.R")

classifications_df <- get_wide_form_taxonomy(taxa_df)

taxa_tree <- get_taxonomic_tree(taxa_df)
print(taxa_tree, "scientific_id", "rank")
taxa_tree_df <- ToDataFrameNetwork(taxa_tree, "scientific_id", "rank", direction = "descend")

oyster_density <- Node$new("Oyster Density and Size Frequency", scientific_id = "PROTOCOL:OYSTER-DENSITY")

#### Oysters ####
oysters <- oyster_density$AddChild("Oysters", 
                            scientific_id = "FUNCTIONAL:OYSTERS",
                            type = "primary")

ids <- c("Ostreidae", "Isognomonidae")
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  oysters$AddChildNode(new_node)
})

#### Non-oyster bivalves ####

bivalves_other_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         !Family %in% c("Ostreidae", "Isognomonidae", "Mytilidae")) %>%
  filter(!is.na(Family))

#### Gastropods ####
gastropods <- oyster_density$AddChild("Gastropods", 
                                   scientific_id = "urn:lsid:marinespecies.org:taxname:101",
                                   type = "primary")

ids <- c("Gastropoda")
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  gastropods$AddChildNode(new_node)
})
