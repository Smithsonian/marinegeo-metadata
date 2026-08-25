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
         !Family %in% c("Ostreidae", "Isognomonidae")) %>%
  filter(!is.na(Family))

bivalves_other <- oyster_density$AddChild("Non-oyster bivalves", 
                                   scientific_id = "FUNCTIONAL:NON-OYSTER-BIVALVES",
                                   type = "primary")

ids <- unique(bivalves_other_wide$Family)
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  bivalves_other$AddChildNode(new_node)
})

#### Gastropods ####
gastropods <- oyster_density$AddChild("Gastropods", 
                                   scientific_id = "urn:lsid:marinespecies.org:taxname:101",
                                   type = "primary")

ids <- c("Gastropoda")
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  gastropods$AddChildNode(new_node)
})

#### All other sessile invertebrates ####
sessile_inverts <- oyster_density$AddChild("Other sessile invertebrates", 
                                           scientific_id = "FUNCTIONAL:OYS_DEN_OTHER_SESSILE_INVERTS",
                                           type = "primary")

sessile_inverts_wide <- classifications_df %>%
  filter(Phylum %in% c("Porifera", "Cnidaria", "Bryozoa", "Brachiopoda") | 
           Subphylum == "Tunicata" | # Chordata
           Subclass == "Cirripedia" | # Barnacles
           Family %in% c("Serpulidae", "Sabellidae") # Polychaetes
  )

ids <- c("Porifera", "Cnidaria", "Bryozoa", 
         "Cirripedia",
         # "Brachiopoda", # None present
         "Tunicata"
         )

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  sessile_inverts$AddChildNode(new_node)
})


polychaetes <- sessile_inverts$AddChild("Polychaeta", 
                                        scientific_id = "urn:lsid:marinespecies.org:taxname:883")

ids <- c("Serpulidae", "Sabellidae")

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  polychaetes$AddChildNode(new_node)
})

# Verify enrollment:
# View(print(oyster_density, "scientific_id", "type", "code", "rank", limit = NULL))

output_network_df <- ToDataFrameNetwork(oyster_density, "scientific_id", "type", "code", "rank", "definition", direction = "descend")
#output_network_df %>% count(scientific_id) %>% filter(n > 1)
output_network_df %>%
  mutate(tree_name = "oyster_density") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/oyster_density.csv")
