library(tidyverse)
library(taxize)

taxa_df <- read_csv("taxonomy-and-functional-groups/taxonomic-lookup/marinegeo_taxonomic_lookup.csv") 

ids <- unique(taxa_df$taxonomic_id)

ids1 <- ids[1:100]
ids2 <- ids[101:200]
ids3 <- ids[201:300]
ids4 <- ids[301:400]
ids5 <- ids[401:500]
ids6 <- ids[501:600]
ids7 <- ids[601:700]
ids8 <- ids[701:800]
ids9 <- ids[801:900]
ids10 <- ids[901:1000]
ids11 <- ids[1001:1100]
ids12 <- ids[1101:1200]
ids13 <- ids[1201:length(ids)]

out1 <- classification(ids1, db="worms")
out2 <- classification(ids2, db="worms")
out3 <- classification(ids3, db="worms")
out4 <- classification(ids4, db="worms")
out5 <- classification(ids5, db="worms")
out6 <- classification(ids6, db="worms")
out7 <- classification(ids7, db="worms")
out8 <- classification(ids8, db="worms")
out9 <- classification(ids9, db="worms")
out10 <- classification(ids10, db="worms")
out11 <- classification(ids11, db="worms")
out12 <- classification(ids12, db="worms")
out13 <- classification(ids13, db="worms")

out <- c(out1, out2, out3, out4, out5, out6, out7, out8, out9, out10, out11, out12, out13)

results <- bind_rows(
  lapply(out, function(i){
    i %>%
      mutate(parent_id = lag(id, n = 1))
  })
) %>%
  distinct() %>%
  mutate(scientific_id = paste0("APHIA:", id)) %>%
  select(scientific_id, everything())

write_csv(results, "taxonomic-lookup/marinegeo_taxonomic_lookup.csv")
