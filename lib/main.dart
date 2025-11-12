import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'core/main_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await GetStorage.init();

  runApp(const MainWrapper());
  // running somthing
}
