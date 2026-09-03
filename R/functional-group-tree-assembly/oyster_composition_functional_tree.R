# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

# Build the tree
oyster_composition <- Node$new("Oyster Reef Composition", scientific_id = "FUNCTIONAL:OYSTER_REEF_COMPOSITION")

# Non-oysters

# Algae
algae <- oyster_composition$AddChild("Algae", scientific_id = "FUNCTIONAL:ALGAE", type = "primary")

# Barnacles
Barnacles <- oyster_composition$AddChild("Barnacles", scientific_id = "FUNCTIONAL:BARNACLES", type = "primary")

# Bivalves (Mussels?)
Bivalves <- oyster_composition$AddChild("Bivalves", scientific_id = "FUNCTIONAL:BIVALVES", type = "primary")

# Ascidians (solitary vs. colonial?)
Ascidians <- oyster_composition$AddChild("Ascidians", scientific_id = "FUNCTIONAL:ASCIDIANS", type = "primary")

# Sponges
Sponges <- oyster_composition$AddChild("Sponges", scientific_id = "FUNCTIONAL:SPONGES", type = "primary")

# Sediment
Sediment <- oyster_composition$AddChild("Sediment", scientific_id = "FUNCTIONAL:SEDIMENT", type = "primary")

# Rock
Rock <- oyster_composition$AddChild("Rock", scientific_id = "FUNCTIONAL:ROCK", type = "primary")

# Oysters:
oysters <- oyster_composition$AddChild("Oyster Material", scientific_id = "FUNCTIONAL:OYSTER")

# Large Shell Material + Cultch
lsm_and_c <- oysters$AddChild("Cultch & Large Shell Material", scientific_id = "FUNCTIONAL:LARGE_SHELL_MATERIAL_AND_CULTCH", type = "primary")

#   Large Shell Material
lsm <- lsm_and_c$AddChild("Large Shell Material", scientific_id = "FUNCTIONAL:LARGE_SHELL_MATERIAL", type = "primary")

#   •	Live oyster
live <- lsm$AddChild("Live Oyster", scientific_id = "FUNCTIONAL:LIVE_OYSTER", type = "primary")

#   •	Gaper oyster (gaping dying oyster with visible tissue, uncommon)
# gaper <- lsm$AddChild("Gaper Oyster", scientific_id = "FUNCTIONAL:GAPER_OYSTER", definition = "gaping dying oyster with visible tissue, uncommon")

#   •	Box oyster (gaping dead with both shells still attached, no visible tissue)
box <- lsm$AddChild("Box Oyster", scientific_id = "FUNCTIONAL:BOX_OYSTER", type = "primary", 
                    definition = "gaping dead with both shells still attached, no visible tissue")

#   Cultch (single intact shells)
cultch <- lsm_and_c$AddChild("Cultch", scientific_id = "FUNCTIONAL:CULTCH", type = "primary", 
                             definition = "single intact shells")

# Shell hash / Shell fragments
shell_hash <- oysters$AddChild("Shell hash", scientific_id = "FUNCTIONAL:SHELL_HASH", type = "primary")

oyster_composition
print(oyster_composition, "scientific_id")
print(oyster_composition, "scientific_id", "definition")

output_network_df <- ToDataFrameNetwork(oyster_composition, "scientific_id", "type", "code", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "oyster_composition") %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/oyster_composition.csv")
