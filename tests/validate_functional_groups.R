library(marinegeo.utils)
library(tidyverse)

df <- read_csv("tests/oyster_height_scientific_names.csv")

df_sci_ids <- df %>%
  mutate(scientific_id = marinegeo.utils::utl_mg_get_scientific_id(scientific_name))

# Cliona = 132026

# Amphibalanus amphitrite = 421137

# Thoracica = 1107

# Angulus texanus = 420862