library(marinegeo.utils)
library(tidyverse)

df <- read_csv("tests/oyster_height_scientific_names.csv")

df_sci_ids <- df %>%
  mutate(scientific_id = marinegeo.utils::utl_mg_get_scientific_id(scientific_name))

unique(marinegeo.utils::utl_mg_get_registry("functional_group_lookup")$tree_name)

View(
df_sci_ids %>%
  mutate(category = marinegeo.utils::utl_mg_assign_functional_groups("oyster_density", 
                                                                     c("Oysters",
                                                                       "Non-oyster bivalves",
                                                                       "Gastropods"), 
                                                                     scientific_name))
)
