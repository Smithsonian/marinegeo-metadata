library(marinegeo.utils)
library(tidyverse)

df <- read_csv("tests/oyster_height_scientific_names.csv")

df_sci_ids <- df %>%
  mutate(scientific_id = marinegeo.utils::utl_mg_get_scientific_id(scientific_name))

# Cliona = urn:lsid:marinespecies.org:taxname:132026

# Amphibalanus amphitrite = urn:lsid:marinespecies.org:taxname:421137

# Thoracica = urn:lsid:marinespecies.org:taxname:1107

# Angulus texanus = urn:lsid:marinespecies.org:taxname:420862