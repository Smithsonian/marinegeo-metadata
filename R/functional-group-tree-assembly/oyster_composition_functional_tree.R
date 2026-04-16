# See data.tree vignette https://cran.r-project.org/web/packages/data.tree/vignettes/data.tree.html

library(data.tree)
library(tidyverse)
library(marinegeo.utils)

# Build the tree
oyster_composition <- Node$new("FUNCTIONAL:OYSTER_REEF_COMPOSITION", node_name = "Oyster Reef Composition")

# Non-oysters

# Algae
algae <- oyster_composition$AddChild("FUNCTIONAL:ALGAE", node_name = "Algae")

# Barnacles
Barnacles <- oyster_composition$AddChild("FUNCTIONAL:BARNACLES", node_name = "Barnacles")

# Bivalves (Mussels?)
Bivalves <- oyster_composition$AddChild("FUNCTIONAL:BIVALVES", node_name = "Bivalves")

# Ascidians (solitary vs. colonial?)
Ascidians <- oyster_composition$AddChild("FUNCTIONAL:ASCIDIANS", node_name = "Ascidians")

# Sponges
Sponges <- oyster_composition$AddChild("FUNCTIONAL:SPONGES", node_name = "Sponges")

# Sediment
Sediment <- oyster_composition$AddChild("FUNCTIONAL:SEDIMENT", node_name = "Sediment")

# Rock
Rock <- oyster_composition$AddChild("FUNCTIONAL:ROCK", node_name = "Rock")

# Oysters:
oysters <- oyster_composition$AddChild("FUNCTIONAL:OYSTER", node_name = "Oyster Material")

# Large Shell Material + Cultch
lsm_and_c <- oysters$AddChild("FUNCTIONAL:LARGE_SHELL_MATERIAL_AND_CULTCH", node_name = "Cultch & Large Shell Material")

#   Large Shell Material  
lsm <- lsm_and_c$AddChild("FUNCTIONAL:LARGE_SHELL_MATERIAL", node_name = "Large Shell Material")

#   •	Live oyster
live <- lsm$AddChild("FUNCTIONAL:LIVE_OYSTER", node_name = "Live Oyster")

#   •	Gaper oyster (gaping dying oyster with visible tissue, uncommon)
gaper <- lsm$AddChild("FUNCTIONAL:GAPER_OYSTER", node_name = "Gaper Oyster", definition = "gaping dying oyster with visible tissue, uncommon")

#   •	Box oyster (gaping dead with both shells still attached, no visible tissue)
box <- lsm$AddChild("FUNCTIONAL:BOX_OYSTER", node_name = "Box Oyster", definition = "gaping dead with both shells still attached, no visible tissue")

#   Cultch (single intact shells)
cultch <- lsm_and_c$AddChild("FUNCTIONAL:CULTCH", node_name = "Cultch", definition = "single intact shells")

# Shell hash / Shell fragments
shell_hash <- oysters$AddChild("FUNCTIONAL:SHELL_HASH", node_name = "Shell hash")

#   shell fragments - closer to a gravel texture)
shell_hash_g <- shell_hash$AddChild("FUNCTIONAL:SHELL_HASH_GRAVEL", node_name = "Shell hash (gravel texture)")

oyster_composition
print(oyster_composition, "node_name")
print(oyster_composition, "node_name", "definition")

output_network_df <- ToDataFrameNetwork(oyster_composition, "node_name", "rank", "definition", direction = "descend")

output_network_df %>%
  mutate(tree_name = "oyster_composition",
         rank = NA) %>%
  select(from, to, node_name, rank, definition, tree_name) %>%
  write_csv("taxonomy-and-functional-groups/functional-group-lookup/oyster_composition.csv")
