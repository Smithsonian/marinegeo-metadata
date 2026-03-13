# marinegeo-metadata

`marinegeo-metadata` contains metadata to support QA/QC and data management of MarineGEO data. A companion R package, `marinegeo.utils`, loads the CSV metadata files found here into its `sysdata.rda`. The `R/` directory in this repository stores scripts not suitable for the R package.

## Repository Structure

```
marinegeo-metadata/
├── README.md
├── marinegeo_data_index.csv
├── docs/                              # Markdown descriptions of each metadata type
├── R/                                 # R scripts not suitable for the `marinegeo.utils` package
├── sites-and-partners/
│   ├── partner-codes/                 # Partner organization codes
│   └── site-names/                    # Site location names by partner
├── table-metadata/
│   ├── categorical-values/            # Controlled vocabularies for categorical fields
│   └── data-structure/                # Column definitions for each data table type
└── taxonomy-and-functional-groups/
    ├── functional-group-lookup/       # Species-to-functional-group mappings
    ├── observation-lookup/            # Observation ID reference tables
    └── taxonomic-lookup/              # Taxonomic reference tables
```

## Documentation

Markdown files for each major type of metadata is in `docs/`:

| Type of Metadata | Markdown File |
|---|---|
| Species names, taxonomic classifications, Aphia IDs, functional groups, observation IDs | `docs/taxonomy_and_functional_groups.md` |
| Partner codes, observatory or project site names, site coordinates | `docs/sites_and_partners.md` |
| Column names, data types, controlled vocabularies, table structure for a protocol | `docs/table_metadata.md` |
