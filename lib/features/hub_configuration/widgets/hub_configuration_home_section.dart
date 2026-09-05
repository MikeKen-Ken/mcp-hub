import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/app_motion.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../screens/client_mcp_screen.dart';
import 'catalog_sync_card.dart';
import 'folder_resource_sync_card.dart';
import 'hub_configuration_bulk_card.dart';
import 'section_header.dart';

class HubConfigurationHomeSection extends StatelessWidget {
  const HubConfigurationHomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<HubController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Hub configuration'),
        const SizedBox(height: 8),
        const HubConfigurationBulkCard(),
        const SizedBox(height: 16),
        const SectionHeader('Catalog'),
        const SizedBox(height: 8),
        CatalogSyncCard(
          onOpenMcpSettings: () {
            pushAppPage<void>(context, const ClientMcpScreen());
          },
        ),
        const SizedBox(height: 16),
        const SectionHeader('Folder resources'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 820;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final resource in AgentResourceKind.values)
                  SizedBox(
                    width: cardWidth,
                    child: FolderResourceSyncCard(resource: resource),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
