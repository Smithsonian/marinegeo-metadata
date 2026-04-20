# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

# Build the tree
oyster_composition <- Node$new("Oyster Reef Composition", scientific_id = "FUNCTIONAL:OYSTER_REEF_COMPOSITION")

# Non-oysters

# Algae
algae <- oyster_composition$AddChild("Algae", scientific_id = "FUNCTIONAL:ALGAE")

# Barnacles
Barnacles <- oyster_composition$AddChild("Barnacles", scientific_id = "FUNCTIONAL:BARNACLES")

# Bivalves (Mussels?)
Bivalves <- oyster_composition$AddChild("Bivalves", scientific_id = "FUNCTIONAL:BIVALVES")

# Ascidians (solitary vs. colonial?)
Ascidians <- oyster_composition$AddChild("Ascidians", scientific_id = "FUNCTIONAL:ASCIDIANS")

# Sponges
Sponges <- oyster_composition$AddChild("Sponges", scientific_id = "FUNCTIONAL:SPONGES")

# Sediment
Sediment <- oyster_composition$AddChild("Sediment", scientific_id = "FUNCTIONAL:SEDIMENT")

# Rock
Rock <- oyster_composition$AddChild("Rock", scientific_id = "FUNCTIONAL:ROCK")

# Oysters:
oysters <- oyster_composition$AddChild("Oyster Material", scientific_id = "FUNCTIONAL:OYSTER")

# Large Shell Material + Cultch
lsm_and_c <- oysters$AddChild("Cultch & Large Shell Material", scientific_id = "FUNCTIONAL:LARGE_SHELL_MATERIAL_AND_CULTCH")

#   Large Shell Material
lsm <- lsm_and_c$AddChild("Large Shell Material", scientific_id = "FUNCTIONAL:LARGE_SHELL_MATERIAL")

#   •	Live oyster
live <- lsm$AddChild("Live Oyster", scientific_id = "FUNCTIONAL:LIVE_OYSTER")

#   •	Gaper oyster (gaping dying oyster with visible tissue, uncommon)
# gaper <- lsm$AddChild("Gaper Oyster", scientific_id = "FUNCTIONAL:GAPER_OYSTER", definition = "gaping dying oyster with visible tissue, uncommon")

#   •	Box oyster (gaping dead with both shells still attached, no visible tissue)
box <- lsm$AddChild("Box Oyster", scientific_id = "FUNCTIONAL:BOX_OYSTER", definition = "gaping dead with both shells still attached, no visible tissue")

#   Cultch (single intact shells)
cultch <- lsm_and_c$AddChild("Cultch", scientific_id = "FUNCTIONAL:CULTCH", definition = "single intact shells")

# Shell hash / Shell fragments
shell_hash <- oysters$AddChild("Shell hash", scientific_id = "FUNCTIONAL:SHELL_HASH")

oyster_composition
print(oyster_composition, "scientific_id")
print(oyster_composition, "scientific_id", "definition")

output_network_df <- ToDataFrameNetwork(oyster_composition, "scientific_id", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "oyster_composition",
         rank = NA) %>%
  select(from, to, scientific_id, rank, definition, tree_name) %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/oyster_composition.csv")
