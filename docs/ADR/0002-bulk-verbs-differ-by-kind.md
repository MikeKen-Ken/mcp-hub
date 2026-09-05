# Bulk verbs are not the same for Catalog and Folder resources

Status: accepted

Download, Merge, and Upload All move Hub configuration (Catalog plus Folder resources). Apply and Convert do not write the Catalog. Apply copies Folder resources from the Hub cache into Cursor. Write to Clients writes the Catalog into Client MCP config. Convert stays Folder resources only.

Automatic WebDAV stays Catalog only. Manual All is the full set. Auto Folder upload would overwrite remote Folder resources with no confirm.

Local backup is the same set as Hub configuration: Catalog plus Folder resources. WebDAV and the local zip are two transports for one set.

On the home page, Catalog (MCP) and Folder resources are two groups on the same page. They are not one grid of five equal cards.

Button names and the bulk Merge confirm are in ADR 0004.
