# Bulk Hub configuration has no 1-2-3 sequence; Merge needs a confirm

Status: accepted

The bulk card is not a numbered cache-apply-upload sequence. Catalog does not use Apply. Download already replaces the Hub Catalog.

Button names use glossary terms:

- Download Hub configuration
- Merge Hub configuration
- Apply Folder resources
- Upload Hub configuration
- Convert Folder resources

Merge Hub configuration shows one confirm. The confirm says Catalog merge changes the Hub list now, Folder resource merge writes the Hub cache, and Cursor folders and Client MCP config do not change.

The same rule applies to Catalog Merge on the MCP card: that merge is live, so it also needs a confirm. Folder resource Merge on a single card stays without a confirm (Hub cache only).
