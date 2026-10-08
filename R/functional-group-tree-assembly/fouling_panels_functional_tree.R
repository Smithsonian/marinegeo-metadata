# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)

obs_df <- read_csv(list.files("taxonomy-and-functional-groups/observation-lookup/", full.names = T))
taxa_df <- read_csv(list.files("taxonomy-and-functional-groups/taxonomic-lookup/", full.names = T))

source("R/taxonomic-lookup-updates/taxonomy_helpers.R")

classifications_df <- get_wide_form_taxonomy(taxa_df)

taxa_tree <- get_taxonomic_tree(taxa_df)
print(taxa_tree, "scientific_id", "rank")
taxa_tree_df <- ToDataFrameNetwork(taxa_tree, "scientific_id", "rank", direction = "descend")

fouling <- Node$new("Fouling Cover", scientific_id = "PROTOCOL:FOULING-COVER")

# phylum: Cnidarians

### Hydroids ####
hydroids_wide <- classifications_df %>%
  filter(Phylum == "Cnidaria",
         Class == "Hydrozoa")

# Cnidaria gets assigned to hydroid

hydroids <- fouling$AddChild("hydroids",
                             scientific_id = "FUNCTIONAL:HYDROIDS",
                             type = "primary",
                             code = "hyd")

ids <- "Hydrozoa"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  hydroids$AddChildNode(new_node)
})

# Class: Anthozoa (corals and sea anemones)

### Anemones ####
anemones_wide <- classifications_df %>%
  filter(Phylum == "Cnidaria",
         Subphylum == "Anthozoa",
         # Class == "Hexacorallia
         Order == "Actiniaria")

anemones <- fouling$AddChild("anemones",
                             scientific_id = "FUNCTIONAL:ANEMONE",
                             type = "primary",
                             code = "ane")

ids <- "Actiniaria"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  anemones$AddChildNode(new_node)
})

### Corals ####
classifications_df %>%
  filter(Phylum == "Cnidaria",
         Subphylum == "Anthozoa",
         Class %in% c("Hexacorallia", "Octocorallia"),
         Order != "Actiniaria")

# No corals in the initial fouling group assignment df

corals <- fouling$AddChild("corals",
                           scientific_id = "FUNCTIONAL:CORALS",
                           type = "primary",
                           code = "coral")

# phylum: Porifera

### Sponges ####
sponges_wide <- classifications_df %>%
  filter(Phylum == "Porifera")

sponges <- fouling$AddChild("sponges",
                             scientific_id = "FUNCTIONAL:SPONGE",
                             type = "primary",
                             code = "spg")

ids <- "Porifera"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  sponges$AddChildNode(new_node)
})

# phylum: Annelida

# Polychaetes (Class: Polychaeta)

### Serpulid Polychaetes ####
serpulids_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         Family == "Serpulidae")

serpulids <- fouling$AddChild("serpulid polychaetes",
                              scientific_id = "FUNCTIONAL:SERPULIDS",
                              type = "primary",
                              code = "ser_poly")

ids <- "Serpulidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  serpulids$AddChildNode(new_node)
})

### Sabellid Polychaetes ####
sabellids_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         Family == "Sabellidae")

sabellids <- fouling$AddChild("sabellid polychaetes",
                             scientific_id = "FUNCTIONAL:SABELLIDS",
                             type = "primary",
                             code = "sab_poly")

ids <- "Sabellidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  sabellids$AddChildNode(new_node)
})

### Other Polychaetes ####
poly_other_wide <- classifications_df %>%
  filter(Phylum == "Annelida",
         Class == "Polychaeta",
         !Family %in% c("Serpulidae", "Sabellidae")) %>%
  filter(!is.na(Family)) # Need to get all non-NA families for enrollment

other_poly <- fouling$AddChild("other polychaetes",
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

### Bivalve Oysters ####
oysters_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         Family %in% c("Ostreidae", "Isognomonidae"))

# Note that Isognomonidae are technically saltwater clams, but are closer to oysters in function
# Currently the family only incorporates Isognomon alatus into this hierarchy

oysters <- fouling$AddChild("bivalve oysters",
                               scientific_id = "FUNCTIONAL:OYSTERS",
                               type = "primary",
                               code = "bi_oys")

ids <- c("Ostreidae", "Isognomonidae")
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  oysters$AddChildNode(new_node)
})

### Bivalve Mussels ####
mussels_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         Family == "Mytilidae")

mussels <- fouling$AddChild("bivalve mussels",
                            scientific_id = "FUNCTIONAL:MUSSELS",
                            type = "primary",
                            code = "bi_mus")

ids <- "Mytilidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  mussels$AddChildNode(new_node)
})

### Other Bivalves ####

# Initial fouling lookup includes families: Arcida, Myida, Margaritidae, Anomiidae
# But total taxonomic lookup includes additional families

bivalves_other_wide <- classifications_df %>%
  filter(Phylum == "Mollusca",
         Class == "Bivalvia",
         !Family %in% c("Ostreidae", "Isognomonidae", "Mytilidae")) %>%
  filter(!is.na(Family))

bivalves_other <- fouling$AddChild("other bivalves",
                            scientific_id = "FUNCTIONAL:FOULING_OTHER_BIVALVES",
                            type = "primary",
                            code = "bi_other")

ids <- unique(bivalves_other_wide$Family)
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  bivalves_other$AddChildNode(new_node)
})

bivalve_clams <- bivalves_other$AddChild("clams",
                                         scientific_id = "FUNCTIONAL:CLAMS")
                                         #type = "primary",
                                         #code = "bi_other")
# phylum: Brachiopoda

### Brachiopods ####

# no occurrences
brachiopods_wide <- classifications_df %>%
  filter(Phylum == "Brachiopoda")

brachiopods <- fouling$AddChild("brachiopods",
                                   scientific_id = "FUNCTIONAL:BRACHIOPODS",
                                   type = "primary",
                                   code = "brach")

# phylum: Bryozoa

## Bryozoans

### Encrusting bryozoans ####
bryo_encrusting_wide <- classifications_df %>%
  #filter(!is.na(Family)) %>%
  filter(Phylum == "Bryozoa",
         Family %in% c("Aeteidae", "Hippopodinidae", "Watersiporidae", "Electridae",
                       "Celleporidae", "Smittinidae", "Schizoporellidae",
                       "Bitectiporidae"))

bryo_encrusting <- fouling$AddChild("encrusting bryozoans",
                                   scientific_id = "FUNCTIONAL:ENCRUSTING_BRYOZOANS",
                                   type = "primary",
                                   code = "e_bryo")

ids <- c("Aeteidae", "Hippopodinidae", "Watersiporidae", "Electridae",
         "Celleporidae", "Smittinidae", "Schizoporellidae",
         "Bitectiporidae")

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  bryo_encrusting$AddChildNode(new_node)
})

### Arborescent bryozoans ####
bryo_arborescent_wide <- classifications_df %>%
  filter(Phylum == "Bryozoa",
         Family %in% c("Bugulidae", "Savignyellidae", "Nolellidae", "Vesiculariidae",
                       "Victorellidae", "Crisiidae",
                       "Catenicellidae", "Candidae", "Vesiculariidae"))

bryo_arborescent <- fouling$AddChild("arborescent bryozoans",
                                   scientific_id = "FUNCTIONAL:ARBORESCENT_BRYOZOANS",
                                   type = "primary",
                                   code = "a_bryo")

ids <- c("Bugulidae", "Savignyellidae", "Nolellidae", "Vesiculariidae",
         "Victorellidae", "Crisiidae",
         "Catenicellidae", "Candidae", "Vesiculariidae")

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  bryo_arborescent$AddChildNode(new_node)
})

# phylum: Chordata

# subphylum: Tunicata

# class: Ascidiacea

## Ascidians

### Colonial ascidians ####

ascidians_colonial_wide <- classifications_df %>%
  filter(Phylum == "Chordata",
         Class == "Ascidiacea",
         (Family %in% c("Clavelinidae", "Didemnidae", "Holozoidae",
                       "Perophoridae", "Polyclinidae", "Polycitoridae") |
            Genus %in% c("Botryllus", "Polyandrocarpa", "Symplegma")))

ascidians_colonial <- fouling$AddChild("colonial ascidians",
                                   scientific_id = "FUNCTIONAL:COLONIAL_ASCIDIANS",
                                   type = "primary",
                                   code = "col_asc")

ids <- c("Clavelinidae", "Didemnidae", "Holozoidae",
         "Perophoridae", "Polyclinidae", "Polycitoridae", # Families
         "Botryllus", "Polyandrocarpa", "Symplegma",
         "Botrylloides") # Genus (see above)

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  ascidians_colonial$AddChildNode(new_node)
})

# Solitary ascidians (sol asci) ####
ascidians_solitary_wide <- classifications_df %>%
  filter(Phylum == "Chordata",
         Class == "Ascidiacea",
         (Family %in% c("Ascidiidae", "Molgulidae", "Pyuridae") |
            Genus %in% c("Styela")))

ascidians_solitary <- fouling$AddChild("solitary ascidians",
                                   scientific_id = "FUNCTIONAL:SOLITARY_ASCIDIANS",
                                   type = "primary",
                                   code = "sol_asci")

ids <- c("Ascidiidae", "Molgulidae", "Pyuridae", #Family
         "Styela") # Genus (see above)

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  ascidians_solitary$AddChildNode(new_node)
})

# phylum: Arthropoda

### Barnacles ####

barnacles_wide <- classifications_df %>%
  filter(Phylum == "Arthropoda",
         Class == "Thecostraca",
         Subclass == "Cirripedia")

barnacles <- fouling$AddChild("barnacles",
                              scientific_id = "FUNCTIONAL:BARNACLES",
                              type = "primary",
                              code = "barn")

ids <- "Cirripedia"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  barnacles$AddChildNode(new_node)
})

### Other Gastropods ####

# I assume this refers to sessile gastropods, which cement or attach shells to surfaces
# Previous key had "Crepidula" and "Vermetid" as distinct categories - is this a missing category in the updated schema?

other_gastropods <- fouling$AddChild("other gastropods",
                              scientific_id = "FUNCTIONAL:FOULING_OTHER_GASTROPODS",
                              type = "primary",
                              code = "crep")

ids <- c("Crepidula", "Vermetidae")
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  other_gastropods$AddChildNode(new_node)
})

### Forams ####
### Forams Phylum: foraminifera
forams_wide <- classifications_df %>%
  filter(Phylum == "Foraminifera")

forams <- fouling$AddChild("forams",
                            scientific_id = "FUNCTIONAL:FORAMS",
                            type = "primary",
                            code = "for")

ids <- "Foraminifera"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  forams$AddChildNode(new_node)
})


# Tube-building amphipods ####

tube_amphipods <- fouling$AddChild("tube-building amphipods",
                           scientific_id = "FUNCTIONAL:TUBE_BUILDING_AMPHIPODS",
                           type = "primary",
                           code = "tube_amp")

# The remaining species are represented by these families, which may or may not
# all be tube-builders: Podoceridae, Melitidae, Ischyroceridae
ids <- c(
  "Cymadusa", "Ericthonius brasiliensis", "Podocerus brasiliensis",
  "Dulichiella appendiculata", "Cerapus cudjoe"
)

# Additional IDs manually added as data comes in
ids <- c("Elasmopus", ids, "Corophiidae")

lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  tube_amphipods$AddChildNode(new_node)
})

## Algae

# Red fleshy algae ####

red_fleshy_algae <- fouling$AddChild("red fleshy algae",
                                   scientific_id = "FUNCTIONAL:RED_FLESHY_ALGAE",
                                   type = "primary",
                                   code = "red_alg")

# Red crust algae ####
red_crust_algae <- fouling$AddChild("red crust algae",
                                     scientific_id = "FUNCTIONAL:RED_CRUST_ALGAE",
                                     type = "primary",
                                     code = "red_crust")

# Coralline algae ####
coralline_algae <- fouling$AddChild("coralline algae",
                                    scientific_id = "FUNCTIONAL:CORALLINE_ALGAE",
                                    type = "primary",
                                    code = "cor_alg")

# Subclass Corallinophycidae covers all calcified red algae (Corallinales,
# Hapalidiales, Sporolithales), e.g. Lithophyllum incrustans, Amphiroa spp.
ids <- "Corallinophycidae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  coralline_algae$AddChildNode(new_node)
})

# Green algae ####
green_algae <- fouling$AddChild("green algae",
                                    scientific_id = "FUNCTIONAL:GREEN_ALGAE",
                                    type = "primary",
                                    code = "gr_alg")

# e.g. Valonia utricularis
ids <- "Chlorophyta"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  green_algae$AddChildNode(new_node)
})

# Brown algae ####
brown_algae <- fouling$AddChild("brown algae",
                                scientific_id = "FUNCTIONAL:BROWN_ALGAE",
                                type = "primary",
                                code = "br_alg")

ids <- "Phaeophyceae"
lapply(ids, function(x){
  new_node <- Clone(FindNode(taxa_tree, x))
  brown_algae$AddChildNode(new_node)
})

# Algal turf ####
algal_turf <- fouling$AddChild("algal turf",
                                scientific_id = "FUNCTIONAL:ALGAL_TURF",
                                type = "primary",
                                code = "turf")

# Sediment ####
sediment <- fouling$AddChild("sediment",
                               scientific_id = "FUNCTIONAL:SEDIMENT",
                               type = "primary",
                               code = "sed")

# Other ####
other <- fouling$AddChild("other",
                             scientific_id = "FUNCTIONAL:FOULING_OTHER",
                             type = "primary",
                             code = "other")

# Considering biofilm here but will leave as uncategorized for now
# biofilm <- other$AddChild("biofilm", scientific_id = "FUNCTIONAL:BIOFILM")

# Open Space ####
open_space <- fouling$AddChild("open space",
                          scientific_id = "FUNCTIONAL:OPEN_SPACE",
                          type = "primary",
                          code = "os")

# Verify enrollment:
# View(print(fouling, "scientific_id", "type", "code", "rank", limit = NULL))

output_network_df <- ToDataFrameNetwork(fouling, "scientific_id", "type", "code", "rank", "definition", direction = "descend")
#output_network_df %>% count(scientific_id) %>% filter(n > 1)
output_network_df %>%
  mutate(tree_name = "fouling") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/fouling_cover.csv")

