# Taxonomy and Functional Groups

Taxonomic and functional group metadata are found in `\taxonomy-and-functional-groups`. There are three sub-directories, each containing a type of metadata. Each CSV file within a sub-directory should share the same column structure and data types. The three types of metadata include: 

1. `observation-lookup`: A row per unique species or functional group name found in a MarineGEO dataset. In our monitoring datasets, this is often the `scientific_name` column. RLS data entry spreadsheets use `Species`.  
2. `taxonomic-lookup`: Contains taxonomic classifications and Aphia identifiers associated with all species or higher level taxonomic rank observations. This is an adjacency table, where each row has a parent ID representing the relevant higher taxonomic rank, if one exists.
3. `functional-group-lookup`: Defines the hierarchical relationships within MarineGEO functional groups and taxonomic ranks. This is an adjacency table, where each row defines the parent and child relationship via the `from` and `to` columns. 

- All observations are assigned a `scientific_id`, which is usually an Aphia ID or a functional group name (e.g., `urn:lsid:marinespecies.org:taxname:123`, `FUNCTIONAL:MACROALGAE`).  The `scientific_id` column links metadata across all three tables. 
- If the ID reflects a taxonomic rank, that rank and each parent rank for that Aphia ID is stored in the `taxonomic_lookup` table.  
- Hierachical tables that nest taxonomic categories under functional groups are stored in the `functional-group-lookup` table. R scripts generate the hierarchical structure for overarching groups. For instance, the `taxonomy-and-functional-groups/functional-group-lookup/vegetation.csv` file is created from `R/functional-group-tree-assembly/vegetation_functional_tree.R`. The `data.tree` package is used to generate and query the tree structures, which are saved as network data frames (CSVs) on output. 
- Any `scientific_id` assigned as a child of a functional group or taxonomic level inherit the nested structure above that level.
- Any `scientific_id`, whether representing a species or a functional group, can be listed within the functional lookup table as a child of another `scientific_id`.  
- If an observation represents a species, genera, or higher rank's specific morphology or functional attribute, the `scientific_id` should reflect the functional group, not the taxonomic rank. The relevant Aphia ID can be set as a parent in the functional group lookup. For instance, Agariciidae spp. can be nested under two functional groups: "Foliose/Plate corals " and "Sub-massive corals". In that case, any child elements under each functional group shouldn't be "Agariciidae", but instead "Agariciidae (Foliose/Plate)" and "Agariciidae (Sub-massive)". This prevents a survey that lists "Agariciidae" from being mistakenly associated to one of it's associated functional groups when no functional group is specified. 

### Adding new observations and IDs to the lookup tables  

1. Format the new `scientific_name` value for the `observation-lookup` table: Remove any open nomenclature signs ("sp.", "spp.", "nov.", etc.), functional group names should be lowercase, ensure case for taxonomic names are correct.  
2. Determine the relevant `scientific_id` value to be associated with a new `scientific_name` value. If a functional group, then use format "FUNCTIONAL:NEW_FUNCTIONAL_ID". If Aphia ID, then "urn:lsid:marinespecies.org:taxname:APHIA-ID-HERE".  
3. Use the `add_new_observation_id(scientific_name, scientific_id)` function (found in "R/observation-lookup-updates/add_new_IDs_observation_lookup.R"), which will append the new `scientific_name` value and its associated `scientific_id` value to the `observation-lookup` table. The function provides several checks to ensure the new addition is valid.  
4. Repeat the process for each `scientific_name` to be added. 
5. Run the "R/taxonomic-lookup-updates/add_new_IDs_taxonomic_lookup.R" script to check if any new taxonomy ranks need to be added to the `taxonomic-lookup` table. 
6. If the new ID is an Aphia ID, rerun any relevant functional group hierarchy scripts found in "taxonomy-and-functional-groups/functional-group-lookup/" and ensure the ID is present. If not, doublecheck that the parent taxonomic category is being added to the tree.  
7. If the new ID is a functional group, add the group to the relevant functional group hierarchy using the same scripts. 
8. Commit any updates to the repository under a new branch. Use a brief branch name without a date or user name/initials (e.g., "red-algae-update" or "indian-river-lagoon-updates", not "bob-updates" or "2026-05-updates"). Create a pull request on GitHub and ensure the repository manager is assigned to review it. 

