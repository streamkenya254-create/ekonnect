import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        // Tells BackButtonIcon to use arrow_back_ios_new (<) on every screen
        platform: TargetPlatform.iOS,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
        ),
        scaffoldBackgroundColor: AppColors.background,

        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          // Makes the auto-implied back button and all action icons white
          iconTheme: IconThemeData(color: Colors.white, size: 22),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),

        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),

        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
          headlineMedium: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
          titleLarge: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark),
          titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textDark),
          bodyLarge:
              TextStyle(fontSize: 15, color: AppColors.textDark),
          bodyMedium:
              TextStyle(fontSize: 14, color: AppColors.textMedium),
          labelLarge:
              TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),

        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),

        // Every AlertDialog: rounded corners + consistent typography
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          titleTextStyle: const TextStyle(
            color: AppColors.textDark,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.textMedium,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      );
}
