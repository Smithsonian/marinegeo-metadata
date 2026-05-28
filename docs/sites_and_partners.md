# Sites and Partners

Site and partner metadata are found in `\sites-and-partners`. There are two sub-directories, each containing a type of metadata. Each CSV file within a sub-directory shares the same column structure and data types. The two types of metadata include:

1. `partner-codes`: One row per MarineGEO partner, with a unique `partner_code` identifier, partner name, affiliated institution, country, and partner type. Partner type is either `observatory` (a long-term MarineGEO monitoring site) or `project` (a site participating in a specific MarineGEO project). Multiple CSVs exist in this directory, usually organized by project or program grouping (e.g., 3M partners, experiment partners, observatories).
2. `site-names`: One row per named sampling site. Each row includes the `partner_code`, `site_code`, human-readable `site_name`, the dominant `habitat` type, and decimal `latitude` and `longitude` coordinates. Multiple CSVs exist in this directory, with one file per partner or partner grouping.

- The `partner_code` column links the two tables and connects to data tables throughout the repository. Partner codes follow the format `[ISO country code]-[3-letter site abbreviation]` (e.g., `USA-MDA`, `BLZ-CBC`).
- The `site_code` column provides a machine readible code per site. It should be universally unique among the MarineGEO database. Site codes follow the format `[3-letter site abbreviation, all uppercase]-[3 number abbreviation with zero padding]` (e.g., `BIS-001`). 
- A partner may have multiple sites listed in `site-names`, one per sampling location.
- Coordinates may be `NA` if a site's location has not yet been recorded.
