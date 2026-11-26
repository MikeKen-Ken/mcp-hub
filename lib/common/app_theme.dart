import 'package:flutter/material.dart';

/// Linear / Raycast 风格极简开发者工作台主题系统。
abstract final class AppTheme {
  static const fontFamily = 'Noto Sans SC';
  static const fontFamilyFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
    'sans-serif',
  ];

  // Light palette
  static const _lightScaffold = Color(0xFFF7F8FA);
  static const _lightSidebar = Color(0xFFF1F3F7);
  static const _lightCard = Color(0xFFFFFFFF);
  static const _lightSubtle = Color(0xFFF2F4F8);
  static const _lightHairline = Color(0xFFE2E6EE);
  static const _lightBorder = Color(0xFFCBD2DF);
  static const _lightPrimary = Color(0xFF0D9488);
  static const _lightOnSurface = Color(0xFF0F172A);
  static const _lightOnVariant = Color(0xFF526077);

  // Dark palette
  static const _darkScaffold = Color(0xFF0D0F12);
  static const _darkSidebar = Color(0xFF12151B);
  static const _darkCard = Color(0xFF161A22);
  static const _darkSubtle = Color(0xFF1D222D);
  static const _darkHairline = Color(0xFF262C38);
  static const _darkBorder = Color(0xFF353E50);
  static const _darkPrimary = Color(0xFF2DD4BF);
  static const _darkOnPrimary = Color(0xFF042F2E);
  static const _darkOnSurface = Color(0xFFEDF2F7);
  static const _darkOnVariant = Color(0xFF8E9AB0);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color sidebarBg(BuildContext context) =>
      isDark(context) ? _darkSidebar : _lightSidebar;

  static Color cardBg(BuildContext context) =>
      isDark(context) ? _darkCard : _lightCard;

  static Color subtleBg(BuildContext context) =>
      isDark(context) ? _darkSubtle : _lightSubtle;

  static Color hairline(BuildContext context) =>
      isDark(context) ? _darkHairline : _lightHairline;

  static Color success(BuildContext context) =>
      isDark(context) ? const Color(0xFF34D399) : const Color(0xFF059669);

  static Color warning(BuildContext context) =>
      isDark(context) ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scaffold = dark ? _darkScaffold : _lightScaffold;
    final card = dark ? _darkCard : _lightCard;
    final subtle = dark ? _darkSubtle : _lightSubtle;
    final hairlineColor = dark ? _darkHairline : _lightHairline;
    final border = dark ? _darkBorder : _lightBorder;
    final primary = dark ? _darkPrimary : _lightPrimary;
    final onPrimary = dark ? _darkOnPrimary : Colors.white;
    final onSurface = dark ? _darkOnSurface : _lightOnSurface;
    final onVariant = dark ? _darkOnVariant : _lightOnVariant;

    final seedScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );
    final scheme = seedScheme.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: dark ? 0.16 : 0.12),
      onPrimaryContainer: dark ? _darkPrimary : const Color(0xFF0F766E),
      secondaryContainer: subtle,
      onSecondaryContainer: onSurface,
      surface: card,
      onSurface: onSurface,
      onSurfaceVariant: onVariant,
      surfaceContainerLowest: scaffold,
      surfaceContainerLow: dark ? _darkSidebar : _lightSidebar,
      surfaceContainer: card,
      surfaceContainerHigh: subtle,
      surfaceContainerHighest: subtle,
      outline: border,
      outlineVariant: hairlineColor,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final textTheme = _buildTextTheme(base.textTheme, onSurface, onVariant);
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    final buttonText = textTheme.labelLarge?.copyWith(fontSize: 13);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        backgroundColor: scaffold,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: onSurface),
        toolbarTextStyle: textTheme.bodyMedium?.copyWith(color: onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: hairlineColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: hairlineColor,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 14),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: onVariant),
        iconColor: onVariant,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        tilePadding: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: buttonShape,
          side: BorderSide(color: border),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: const WidgetStatePropertyAll(buttonShape),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontSize: 12.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: subtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hairlineColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hairlineColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: hairlineColor),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF252B37) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    TextTheme base,
    Color onSurface,
    Color onVariant,
  ) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: onVariant,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: onVariant,
      ),
    );
  }
}
