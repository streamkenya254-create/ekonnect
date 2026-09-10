/// Central references to bundled image/icon assets.
class AppAssets {
  AppAssets._();

  static const _img = 'assets/images';

  /// White, transparent brand logo — use on dark/purple backgrounds only.
  static const logo = '$_img/logo.png';

  /// The purple mark: a filled disc that carries its own background, so it
  /// reads directly on white without a plate behind it.
  static const logoPurple = 'assets/icon/logo-purple.png';

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

  /// The illustration for an emergency type. The app draws these on the SOS
  /// selector, so a record of that same emergency should not switch to a
  /// different, flat icon set when you look it up later.
  static String forIncident(String type) {
    switch (type) {
      case 'fire':
        return fire;
      case 'flood':
        return flood;
      case 'security':
        return security;
      default:
        return medical;
    }
  }

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
