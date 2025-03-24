import 'package:url_launcher/url_launcher.dart';

Future<void> sendInvite(String roomId, String password) async {
  final Uri uri = Uri.parse(
    "openchase://invite?roomId=$roomId&password=$password",
  );

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    throw 'Could not launch invite link';
  }
}
