import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.primaryDark, // Deep background base
      body: Stack(
        children: [
          // 1. Creative Background: Simulated Mesh/Glow Effect
          Positioned(
            top: -size.width * 0.3,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
          Positioned(
            bottom: size.height * 0.2,
            right: -size.width * 0.3,
            child: Container(
              width: size.width,
              height: size.width,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
          // Blur overlay for the glass effect on the background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: const SizedBox(),
            ),
          ),

          // 2. Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // --- NEW: Ambulance Image at the top ---
                  // Ensure you add an ambulance image to your assets
                  Center(
                    child: Container(
                       decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 20,
                              spreadRadius: 2,
                              offset: Offset(0, 10),
                            )
                          ]
                        ),
                      child: Image.asset(
                        'assets/images/ambulance.png', 
                        width: size.width * 0.7, 
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.airport_shuttle, size: 100, color: Colors.white,), // Fallback if image not found
                      ),
                    ),
                  ),
                  
                  const Spacer(flex: 1),

                  // Enhanced Typography
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontFamily: 'Roboto', // Replace with your app's font
                        color: Colors.white,
                        fontSize: 40,
                        height: 1.1,
                        letterSpacing: -1.0,
                      ),
                      children: [
                        TextSpan(
                          text: 'Emergency help,\n',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: 'one tap away.',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reach verified ambulance crews and practitioners near you, and watch them arrive in real-time.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.5,
                      letterSpacing: 0.2,
                    ),
                  ),

                  // --- REMOVED: Feature Cards ---

                  const Spacer(flex: 2),

                  // 3. Anchored Action Buttons
                  // Wrapped in a column to ensure they remain highly visible at the bottom
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => _open(context, startOnSignUp: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryDark,
                          elevation: 8,
                          shadowColor: Colors.black45,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Create an account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _open(context, startOnSignUp: false),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(double.infinity, 60),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: const Text(
                          'I already have an account',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, {required bool startOnSignUp}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(startOnSignUp: startOnSignUp),
      ),
    );
  }
}