import 'package:flutter/material.dart';

/// Everything the app looks like, in one file.
///
/// Colour, type and spacing used to be split between `constants.dart` and a
/// hundred hand-written `TextStyle`s at the call sites, which is why the same
/// idea came out at 26px on one screen and 11px on another. This file is the
/// only place any of it is decided; `constants.dart` re-exports it, so every
/// screen already has it in scope.
///
/// The voice is the home screen's: large confident headings, generous
/// spacing, and body text you can read at arm's length while something is
/// going wrong.

// ── Colour ─────────────────────────────────────────────────────────────────

/// Three colours: white, deep purple, coral — plus neutral greys for text and
/// dividers. Every legacy name is kept as an alias onto the palette so the
/// whole app re-skins from here.
class AppColors {
  // ── Core palette ────────────────────────────────────────────────
  static const primary = Color(0xFF3D1152); // deep purple — brand / chrome
  static const accent = Color(0xFFFF4D5E); // coral red — action / emergency
  static const surface = Colors.white;

  // Purple tints used sparingly for depth (still "the purple").
  static const primaryDark = Color(0xFF1E0830);
  static const primarySoft = Color(0xFFF3EEF8); // faint purple wash on white

  // Neutral light-grey card surface (Bolt-style tiles).
  static const surfaceAlt = Color(0xFFF1F1F4);

  // ── Neutrals ────────────────────────────────────────────────────
  static const background = Color(0xFFFAF9FC); // near-white
  static const textDark = Color(0xFF1B1524);
  static const textMedium = Color(0xFF6B6675);
  static const textLight = Color(0xFFA7A2B2);
  static const divider = Color(0xFFEBE7F1);

  // ── Semantic aliases (mapped onto the palette) ──────────────────
  static const secondary = primary;
  static const emergency = accent;
  static const success = primary;
  static const warning = accent;
  static const info = primary;

  // ── Incident-type colours — unified to the palette ──────────────
  static const fireColor = primary;
  static const medicalColor = primary;
  static const floodColor = primary;
  static const securityColor = primary;
}

// ── Type ───────────────────────────────────────────────────────────────────

/// The one type scale, so a heading means the same thing on every screen.
class AppText {
  AppText._();

  /// The name of the screen you are on. One per page.
  static const pageTitle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: AppColors.textDark);

  /// The line under a page title.
  static const pageSubtitle = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textMedium);

  /// White page titles, for coloured app bars and gradient heroes.
  static const pageTitleOnColor = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: Colors.white);

  /// Bars that carry the page name rather than a hero.
  static const appBarTitle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: AppColors.textDark);

  /// A division within a page — "Registered with", a month, a settings group.
  static const sectionTitle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: AppColors.textDark);

  /// The heading of one card or row.
  static const cardTitle = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark);

  /// Ordinary reading text inside a card.
  static const body =
      TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMedium);

  /// Emphasised body — a value the eye should land on.
  static const bodyStrong = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark);

  /// Timestamps, counts, captions — supporting detail, never the point.
  static const meta = TextStyle(
      fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textLight);

  /// Text inside a chip or pill.
  static const chip = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

  /// The small label above a field or value.
  static const fieldLabel = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: AppColors.textLight);

  static const button = TextStyle(
      fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.2);
}

// ── Spacing and shape ──────────────────────────────────────────────────────

/// The gaps between things.
///
/// Named steps rather than free numbers: the home screen breathes because its
/// rhythm is 16 / 24 / 32, and a screen that invents 7 and 13 next to it reads
/// as a different app.
class AppSpacing {
  AppSpacing._();

  /// Between a label and its value.
  static const xs = 6.0;

  /// Between rows inside a card.
  static const sm = 10.0;

  /// The standard gap, and the padding inside a card.
  static const md = 16.0;

  /// Page margins, and the gap between cards.
  static const lg = 24.0;

  /// Between one section of a page and the next.
  static const xl = 32.0;

  /// Page padding, left and right.
  static const page = EdgeInsets.symmetric(horizontal: 20);

  /// A card's inner padding.
  static const card = EdgeInsets.all(16);
}

/// Corner radii. Bigger surfaces get rounder corners, consistently.
class AppRadius {
  AppRadius._();

  /// Chips and pills.
  static const chip = 20.0;

  /// Inputs and small buttons.
  static const control = 14.0;

  /// Cards and tiles.
  static const card = 18.0;

  /// Sheets, dialogs and heroes.
  static const sheet = 24.0;
}

// ── The theme ──────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        // Tells BackButtonIcon to use arrow_back_ios_new (<) on every screen
        platform: TargetPlatform.iOS,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        dividerColor: AppColors.divider,

        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          // Same size and weight as a white-barred page's title, so moving
          // between a purple bar and a white one is not a change of voice.
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          // Makes the auto-implied back button and all action icons white
          iconTheme: IconThemeData(color: Colors.white, size: 22),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),

        // Tall enough to be an easy target with one hand while moving.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.divider,
            disabledForegroundColor: AppColors.textLight,
            elevation: 0,
            // Height only. An infinite *minimum width* is an invalid
            // constraint anywhere the width is unbounded — a Row, a dialog
            // action bar — and throws 'BoxConstraints forces an infinite
            // width' during layout. Buttons that should fill the page get
            // that from their parent (a stretch Column or a ListView).
            minimumSize: const Size(64, 56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control)),
            textStyle: AppText.button,
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.divider, width: 1.5),
            // Height only. An infinite *minimum width* is an invalid
            // constraint anywhere the width is unbounded — a Row, a dialog
            // action bar — and throws 'BoxConstraints forces an infinite
            // width' during layout. Buttons that should fill the page get
            // that from their parent (a stretch Column or a ListView).
            minimumSize: const Size(64, 56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control)),
            textStyle: AppText.button,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          // What was typed matters more than the label above it.
          hintStyle: const TextStyle(
              fontSize: 15, color: AppColors.textLight),
          labelStyle: const TextStyle(
              fontSize: 15, color: AppColors.textMedium),
          floatingLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColors.emergency),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),

        cardTheme: CardThemeData(
          elevation: 0,
          shadowColor: Colors.black12,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: const BorderSide(color: AppColors.divider),
          ),
          color: Colors.white,
        ),

        listTileTheme: const ListTileThemeData(
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          titleTextStyle: AppText.bodyStrong,
          subtitleTextStyle: AppText.meta,
          iconColor: AppColors.textMedium,
        ),

        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceAlt,
          labelStyle: AppText.chip.copyWith(color: AppColors.textDark),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip)),
        ),

        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMedium,
          indicatorColor: AppColors.primary,
          labelStyle:
              TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          ),
        ),

        drawerTheme: const DrawerThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),

        // Mapped onto AppText so an unstyled Text and a deliberately styled
        // one land on the same scale instead of drifting apart.
        textTheme: const TextTheme(
          headlineLarge: AppText.pageTitle,
          headlineMedium: AppText.pageTitle,
          titleLarge: AppText.sectionTitle,
          titleMedium: AppText.cardTitle,
          bodyLarge: AppText.bodyStrong,
          bodyMedium: AppText.body,
          labelLarge: AppText.button,
          labelMedium: AppText.chip,
          labelSmall: AppText.meta,
        ),

        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textDark,
          contentTextStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control)),
        ),

        // Every AlertDialog: rounded corners + consistent typography
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sheet)),
          titleTextStyle: AppText.sectionTitle,
          contentTextStyle: const TextStyle(
            color: AppColors.textMedium,
            fontSize: 15,
            height: 1.55,
          ),
        ),
      );
}
