# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)

obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))
taxa_df <- read_csv(list.files("taxonomy-and-functional-groups/taxonomic-lookup/", full.names = T))

source("R/taxonomic-lookup-updates/taxonomy_helpers.R")

classifications_df <- get_wide_form_taxonomy(taxa_df)

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
  
taxa_tree <- get_taxonomic_tree(taxa_df)
print(taxa_tree, "scientific_id", "rank")
taxa_tree_df <- ToDataFrameNetwork(taxa_tree, "scientific_id", "rank", direction = "descend")

fouling <- Node$new("Fouling Cover", scientific_id = "PROTOCOL:FOULING-COVER")

# phylum: Cnidarians

### Hydroids
hydroids_wide <- classifications_df %>%
  filter(Phylum == "Cnidaria",
         Class == "Hydrozoa")

# Cnidaria gets assigned to hydroid
fouling_group_assignments %>%
  filter(fg == "Hydroid",
         !scientific_id %in% hydroids_wide$scientific_id)

hydroids <- fouling$AddChild("Hydroids", 
                             scientific_id = "FUNCTIONAL:HYDROIDS",
                             type = "primary",
                             code = "hyd")

ids <- "Hydrozoa"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  hydroids$AddChildNode(new_node)
})

# Class: Anthozoa (corals and sea anemones)

### Anemones
anemones_wide <- classifications_df %>%
  filter(Phylum == "Cnidaria",
         Subphylum == "Anthozoa",
         # Class == "Hexacorallia
         Order == "Actiniaria")

# Two species are undefined
fouling_group_assignments %>%
  filter(fg == "Anemone",
         !scientific_id %in% anemones_wide$scientific_id)

anemones <- fouling$AddChild("Anemones", 
                             scientific_id = "FUNCTIONAL:ANEMONES",
                             type = "primary",
                             code = "ane")

ids <- "Actiniaria"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  anemones$AddChildNode(new_node)
})

### Corals
classifications_df %>%
  filter(Phylum == "Cnidaria",
         Subphylum == "Anthozoa",
         Class %in% c("Hexacorallia", "Octocorallia"),
         Order != "Actiniaria")

# No corals in the initial fouling group assignment df

corals <- fouling$AddChild("Corals", 
                           scientific_id = "FUNCTIONAL:CORALS",
                           type = "primary",
                           code = "coral")

# phylum: Porifera

### Sponges
sponges_wide <- classifications_df %>%
  filter(Phylum == "Porifera")

# two species are undefined
fouling_group_assignments %>%
  filter(fg == "Sponge",
         !scientific_id %in% sponges_wide$scientific_id)

sponges <- fouling$AddChild("Sponges", 
                             scientific_id = "FUNCTIONAL:SPONGES",
                             type = "primary",
                             code = "spg")

ids <- "Porifera"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  sponges$AddChildNode(new_node)
})

# phylum: Annelida

# Polychaetes (Class: Polychaeta)

### Serpulid Polychaetes
serpulids_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         Family == "Serpulidae")
        
# Two undefined species
fouling_group_assignments %>%
  filter(fg == "Serpulidae",
         !scientific_id %in% serpulids_wide$scientific_id)

serpulids <- fouling$AddChild("Serpulid Polychaetes", 
                              scientific_id = "FUNCTIONAL:SERPULIDS",
                              type = "primary",
                              code = "ser_poly")

ids <- "Serpulidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  serpulids$AddChildNode(new_node)
})

### Sabellid Polychaetes
sabellids_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         Family == "Sabellidae")

fouling_group_assignments %>%
  filter(fg == "Sabellid",
         !scientific_id %in% sabellids_wide$scientific_id)

sabellids <- fouling$AddChild("Sabellid Polychaetes", 
                             scientific_id = "FUNCTIONAL:SABELLIDS",
                             type = "primary",
                             code = "sab_poly")

ids <- "Sabellidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  sabellids$AddChildNode(new_node)
})

### Other Polychaetes
poly_other_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         !Family %in% c("Sabellidae", "Sabellidae")) %>%
  filter(!is.na(Family)) # Need to get all non-NA families for enrollment

# One undefined species
fouling_group_assignments %>%
  filter(fg == "Other polychaetes",
         !scientific_id %in% poly_other_wide$scientific_id)

other_poly <- fouling$AddChild("Other Polychaetes", 
                              scientific_id = "FUNCTIONAL:NON_SER_SAB_POLY",
                              type = "primary",
                              code = "other_poly")

ids <- unique(poly_other_wide$Family)
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  other_poly$AddChildNode(new_node)
})

# phylum: Mollusca

# class: Bivalves

### Bivalve Oysters
oysters_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         Family %in% c("Ostreidae", "Isognomonidae"))

# Note that Isognomonidae are technically saltwater clams, but are closer to oysters in function
# Currently the family only incorporates Isognomon alatus into this hierarchy

fouling_group_assignments %>%
  filter(fg == "Oyster",
         !scientific_id %in% oysters_wide$scientific_id)

### Bivalve Mussels
mussels_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         Family == "Mytilidae")

fouling_group_assignments %>%
  filter(fg == "Mussels",
         !scientific_id %in% mussels_wide$scientific_id)

### Other Bivalves
bivalve_ids <- fouling_group_assignments %>%
  filter(fg == "Other bivalves") %>%
  filter(!is.na(scientific_id)) %>%
  pull(scientific_id)

classifications_df %>%
  filter(scientific_id %in% bivalve_ids) %>%
  count(Phylum, Subphylum, Class, Order, Family)

# Initial fouling lookup includes families: Arcida, Myida, Margaritidae, Anomiidae
# But total taxonomic lookup includes additional families

bivalves_other_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         !Family %in% c("Ostreidae", "Isognomonidae", "Mytilidae"))

# phylum: Brachiopoda

### Brachiopods

# no occurrences
brachiopods_wide <- classifications_df %>%
  filter(Phylum == "Brachiopoda")

# phylum: Bryozoa

## Bryozoans

bryo_ids <- fouling_group_assignments %>%
  filter(fg %in% c("Encrusting bryozoan", "Arborescent bryozoan")) %>%
  filter(!is.na(scientific_id)) %>%
  count(fg, scientific_id)

classifications_df %>%
  filter(scientific_id %in% bryo_ids$scientific_id) %>%
  left_join(bryo_ids)

### Encrusting bryozoans
bryo_encrusting_wide <- classifications_df %>%
  #filter(!is.na(Family)) %>%
  filter(Phylum == "Bryozoa",
         Family %in% c("Aeteidae", "Hippopodinidae", "Watersiporidae", "Electridae", 
                       "Celleporidae", "Smittinidae", "Schizoporellidae", 
                       "Bitectiporidae"))

# 3 undefined, 1 "bryozoa" label
fouling_group_assignments %>%
  filter(fg == "Encrusting bryozoan",
         !scientific_id %in% bryo_encrusting_wide$scientific_id)

### Arborescent bryozoans
bryo_arborescent_wide <- classifications_df %>%
  filter(Phylum == "Bryozoa",
         Family %in% c("Bugulidae", "Savignyellidae", "Nolellidae", "Vesiculariidae", 
                       "Victorellidae", "Crisiidae", "Sertulariidae", 
                       "Catenicellidae", "Candidae", "Vesiculariidae"))

# 2 undefined, 1 "Tridentata" label (thought this went into encrusting?)
fouling_group_assignments %>%
  filter(fg == "Arborescent bryozoan",
         !scientific_id %in% bryo_arborescent_wide$scientific_id)

# phylum: Chordata

# subphylum: Tunicata

# class: Ascidiacea

## Ascidians

ascidian_ids <- fouling_group_assignments %>%
  filter(fg %in% c("Colonial ascidian", "Solitary ascidian")) %>%
  filter(!is.na(scientific_id)) %>%
  count(fg, scientific_id)

classifications_df %>%
  filter(scientific_id %in% ascidian_ids$scientific_id) %>%
  left_join(ascidian_ids)

# Colonial ascidians
ascidians_colonial_wide <- classifications_df %>%
  filter(Phylum == "Chordata",
         Class == "Ascidiacea",
         (Family %in% c("Clavelinidae", "Didemnidae", "Holozoidae",
                       "Perophoridae", "Polyclinidae", "Polycitoridae") | 
            Genus %in% c("Botryllus", "Polyandrocarpa", "Symplegma")))

# 1 undefined ID
fouling_group_assignments %>%
  filter(fg == "Colonial ascidian",
         !scientific_id %in% ascidians_colonial_wide$scientific_id)

# Solitary ascidians
ascidians_solitary_wide <- classifications_df %>%
  filter(Phylum == "Chordata",
         Class == "Ascidiacea",
         (Family %in% c("Ascidiidae", "Molgulidae", "Pyuridae") | 
            Genus %in% c("Styela")))

fouling_group_assignments %>%
  filter(fg == "Solitary ascidian",
         !scientific_id %in% ascidians_solitary_wide$scientific_id)

# phylum: Arthropoda

### Barnacles
barnacle_ids <- fouling_group_assignments %>%
  filter(!is.na(scientific_id)) %>%
  filter(fg == "Barnacles") %>%
  count(fg, scientific_id)
  
classifications_df %>%
  filter(scientific_id %in% barnacle_ids$scientific_id) %>%
  left_join(barnacle_ids)

barnacles_wide <- classifications_df %>%
  filter(Phylum == "Arthropoda",
         Class == "Thecostraca",
         Subclass == "Cirripedia")

fouling_group_assignments %>%
  filter(fg == "Barnacles",
         !scientific_id %in% barnacles_wide$scientific_id)

### Other Gastropods

# I assume this refers to sessile gastropods, which cement or attach shells to surfaces
# Previous key had "Crepidula" and "Vermetid" as distinct categories - is this a missing category in the updated schema?


### Forams Phylum: foraminifera
forams_wide <- classifications_df %>%
  filter(Phylum == "Foraminifera")

# No species in lookup
fouling_group_assignments %>%
  filter(scientific_id %in% forams_wide$scientific_id)

forams <- fouling$AddChild("Forams", 
                            scientific_id = "FUNCTIONAL:FORAMS",
                            type = "primary",
                            code = "for")

ids <- "Foraminifera"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  forams$AddChildNode(new_node)
})


# Tube-building amphipods
tube_amphipod_ids <- fouling_group_assignments %>%
  filter(fg == "Amphipod tubes") %>%
  filter(!is.na(scientific_id)) %>%
  count(resolver, scientific_id)

classifications_df %>%
  filter(scientific_id %in% tube_amphipod_ids$scientific_id) %>%
  count(Phylum, Subphylum, Class, Order, Family)

# Leave this open.. what other types of amphipods are in the lookup? I assume they are all in the mobile grouping

tube_amphipods <- fouling$AddChild("Tube-building amphipods", 
                           scientific_id = "FUNCTIONAL:TUBE_BUILDING_AMPHIPODS",
                           type = "primary",
                           code = "tube_amp")

ids <- taxa_df %>%
  filter(name %in% tube_amphipod_ids$resolver) %>%
  filter(!str_detect(name, "Elasmopus")) %>%
  pull(name)

# This is a tricky one because I don't know where a tube-builder and other amphipod 
# can be separated taxonomically. I'm adding species names and one genus directly
# as child nodes. 
# Elasmopus needs to be added separated to avoid having the species get double registered. 
ids <- c("Elasmopus", ids)

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  tube_amphipods$AddChildNode(new_node)
})

## Algae
 
# All can be assigned as functional groups
# No current species IDs in fouling lookup

# Red fleshy algae

red_fleshy_algae <- fouling$AddChild("Red fleshy algae", 
                                   scientific_id = "FUNCTIONAL:RED_FLESHY_ALGAE",
                                   type = "primary",
                                   code = "red_alg")

# Red crust algae
red_crust_algae <- fouling$AddChild("Red crust algae", 
                                     scientific_id = "FUNCTIONAL:RED_CRUST_ALGAE",
                                     type = "primary",
                                     code = "red_crust")

# Coralline algae
coralline_algae <- fouling$AddChild("Coralline algae", 
                                    scientific_id = "FUNCTIONAL:CORALLINE_ALGAE",
                                    type = "primary",
                                    code = "cor_alg")

# Green algae
green_algae <- fouling$AddChild("Green algae", 
                                    scientific_id = "FUNCTIONAL:GREEN_ALGAE",
                                    type = "primary",
                                    code = "gr_alg")

# Brown algae
brown_algae <- fouling$AddChild("Brown algae", 
                                scientific_id = "FUNCTIONAL:BROWN_ALGAE",
                                type = "primary",
                                code = "br_alg")

# Algal turf
algal_turf <- fouling$AddChild("Algal turf", 
                                scientific_id = "FUNCTIONAL:ALGAL_TURF",
                                type = "primary",
                                code = "turf")

# Sediment
sediment <- fouling$AddChild("Sediment", 
                               scientific_id = "FUNCTIONAL:SEDIMENT",
                               type = "primary",
                               code = "sed")

# Other
other <- fouling$AddChild("Other", 
                             scientific_id = "FUNCTIONAL:FOULING_OTHER",
                             type = "primary",
                             code = "other")

# Open Space
open_space <- fouling$AddChild("Open space", 
                          scientific_id = "FUNCTIONAL:OPEN_SPACE",
                          type = "primary",
                          code = "os")

fouling
print(fouling, "scientific_id")

# Verify enrollment:
# View(print(fouling, "scientific_id", "type", "code", "rank", limit = NULL))

output_network_df <- ToDataFrameNetwork(fouling, "scientific_id", "type", "code", "rank", direction = "descend")

output_network_df %>%
  mutate(tree_name = "fouling") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/fouling_cover.csv")
