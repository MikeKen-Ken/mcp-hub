# Catalog Download in All is live; sync_webdav stays Catalog; All continues after a pack error

Status: accepted

When Download All runs, Catalog Download replaces the Hub Catalog now. Folder resource Download still writes only the Hub cache. There is no Catalog cache.

The hubMCP tool sync_webdav stays Catalog merge then Catalog upload. It does not move Folder resources. Agents that call it must not overwrite remote Folder resources.

If one pack in Download, Merge, or Upload All fails, the Hub still tries the other packs. It reports each result. The action is a failure if any pack failed. There is no rollback of packs that already wrote to WebDAV or to the Hub.
