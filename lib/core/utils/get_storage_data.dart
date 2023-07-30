import 'package:get_storage/get_storage.dart';

class GetStorageData {
  static dynamic getData(String value) {
    final box = GetStorage();
    return box.read(value);
  }

  static writeData(String key, dynamic data) async {
    final box = GetStorage();
    await box.write(key, data);
  }
}
