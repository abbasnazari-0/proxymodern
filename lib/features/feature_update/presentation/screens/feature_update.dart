import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/mytext.dart';

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset('assets/lotties/update.json', width: size.width * 0.6),
            const MyText(
              txt: 'آپدیت جدید در دسترس است',
              size: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            // button
            ElevatedButton(
              onPressed: () async {
                await canLaunchUrl(Uri.parse(url))
                    ? launch(url)
                    : print('cant launch url');
              },
              child: const MyText(
                txt: 'دانلود',
                size: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
