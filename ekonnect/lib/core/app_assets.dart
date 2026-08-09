/// Central references to bundled image/icon assets.
class AppAssets {
  AppAssets._();

  static const _img = 'assets/images';

  /// White, transparent brand logo — use on dark/purple backgrounds only.
  static const logo = '$_img/logo.png';

  // Colorful illustrated SVG icons.
  static const medical = '$_img/doctor.svg';
  static const fire = '$_img/fire.svg';
  static const flood = '$_img/flood.svg';
  static const security = '$_img/police.svg';
  static const ambulance = '$_img/ambulance.svg';
  static const doctor = '$_img/doctor.svg';
  static const call = '$_img/call.svg';
  static const history = '$_img/history.svg';
  static const tutorial = '$_img/tutorial.svg';
  static const user = '$_img/user.svg';
  static const practitioner = '$_img/doctor.svg';
  static const noInternet = '$_img/no-internet.svg';
  static const ambulanceHome = '$_img/ambulance_home.svg';
  static const google = '$_img/google.svg';
  static const mic = '$_img/mic.svg';

  /// The big illustrated icon that represents a given role.
  static String forRole(String role) {
    switch (role) {
      case 'ambulance':
        return ambulance;
      case 'practitioner':
        return practitioner;
      default:
        return user;
    }
  }
}
