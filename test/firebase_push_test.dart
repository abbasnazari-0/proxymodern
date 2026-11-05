import 'package:flutter_test/flutter_test.dart';
import 'package:proxymodern/core/utils/constans.dart';
import 'package:proxymodern/core/utils/notification_service.dart';

void main() {
  group('NotificationService', () {
    test('every install listens to the "all" topic', () {
      expect(NotificationService.allTopic, 'all');
      expect(NotificationService.allTopic, firebaseTopicAll);
    });

    test('channel id is the one declared in the Android manifest', () {
      expect(NotificationService.channelId, 'general_notifications');
      expect(NotificationService.channelName, isNotEmpty);
      expect(NotificationService.channelDescription, isNotEmpty);
    });
  });
}
