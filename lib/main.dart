import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'core/main_wrapper.dart';
import 'core/utils/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 راه‌اندازی Firebase (Analytics + Performance + Messaging).
  // اگر Google Play services روی دستگاه نباشد، اپ بدون Firebase ادامه می‌یابد.
  try {
    await FirebaseService.instance.initialize();
  } catch (error) {
    debugPrint('Firebase init failed: $error');
  }

  // تنظیمات در GetStorage نگهداری می‌شود؛ باید قبل از runApp آماده شود.
  try {
    await GetStorage.init();
  } catch (error) {
    debugPrint('GetStorage init failed: $error');
  }

  runApp(const MainWrapper());
}
