import 'package:flutter/material.dart';
import '../../core/constants.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.warning_amber_rounded,
      color: AppColors.emergency,
      title: 'Spot an Emergency',
      body:
          'When you face any emergency — medical, fire, flood or security threat — open eKonnect immediately.',
      tip: '📍 Keep location services ON at all times.',
    ),
    _Slide(
      icon: Icons.touch_app_rounded,
      color: AppColors.medicalColor,
      title: 'Tap the SOS Button',
      body:
          'From the home screen tap the matching SOS button for your emergency type. Confirm when prompted.',
      tip: '🚨 Your GPS location is shared automatically.',
    ),
    _Slide(
      icon: Icons.radar,
      color: AppColors.securityColor,
      title: 'Responder is Alerted',
      body:
          'Nearby responders instantly receive your location and emergency type. The nearest available one will accept your request.',
      tip: '⏱ Average response time: under 5 minutes.',
    ),
    _Slide(
      icon: Icons.map_rounded,
      color: AppColors.success,
      title: 'Track in Real Time',
      body:
          'Once a responder accepts, you see their live location on the map moving towards you.',
      tip: '🗺️ Blue dot = responder, Red dot = you.',
    ),
    _Slide(
      icon: Icons.chat_bubble_rounded,
      color: AppColors.secondary,
      title: 'Chat & Call',
      body:
          'Once assigned, use the Chat or Call button to communicate directly with your responder.',
      tip: '📞 You can also call 999 any time from the emergency bar.',
    ),
    _Slide(
      icon: Icons.smart_toy_rounded,
      color: AppColors.primary,
      title: 'AI Emergency Assistant',
      body:
          'Not sure what to do? Open the AI Assistant from the menu. It gives first-aid guidance while you wait for help.',
      tip: '🤖 Works best with an active internet connection.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('How It Works'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (context, i) => _SlideWidget(slide: _slides[i]),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.primary : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _page == _slides.length - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String tip;
  const _Slide(
      {required this.icon,
      required this.color,
      required this.title,
      required this.body,
      required this.tip});
}

class _SlideWidget extends StatelessWidget {
  final _Slide slide;
  const _SlideWidget({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 56, color: slide.color),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                color: AppColors.textMedium,
                height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: slide.color.withValues(alpha: 0.2)),
            ),
            child: Text(
              slide.tip,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: slide.color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
