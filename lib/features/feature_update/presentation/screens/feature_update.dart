import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Update screen driven by `setting.version` / `should_update` / `update_*`.
///
/// - [forced] = true: this is the app root, there is no "later" button and
///   back does not leave it (only closing the app does). Reopening the app runs
///   the splash check again, so the screen keeps coming back until the new
///   build is installed.
/// - [forced] = false: "بعداً" calls [onLater] (or pops) and the user can
///   continue using the current version.
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({
    super.key,
    required this.url,
    this.title,
    this.description,
    this.forced = false,
    this.onLater,
  });

  final String url;
  final String? title;
  final String? description;
  final bool forced;
  final VoidCallback? onLater;

  static const _bg = Color(0xFF081016);
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  static TextStyle _text({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = Colors.white,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'vazir',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  Future<void> _openDownload(BuildContext context) async {
    final raw = url.trim();
    final uri = Uri.tryParse(raw);
    final valid =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (!valid) {
      _showMessage(context, 'لینک دانلود از سرور خالی یا نامعتبر است.');
      return;
    }

    // The download button must stay enabled in forced mode; a failure is
    // reported to the user instead of silently disabling it.
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      _showMessage(context, 'باز کردن لینک دانلود ممکن نشد:\n$raw');
    }
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: _text(size: 13),
          ),
          backgroundColor: _card,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  void _later() {
    if (forced) return;
    final callback = onLater;
    if (callback != null) {
      callback();
    } else {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : (forced ? 'به‌روزرسانی الزامی' : 'به‌روزرسانی جدید');
    final body = (description ?? '').trim();

    return PopScope(
      // Back never leaves the update screen: forced mode ignores it, optional
      // mode treats it like "بعداً" so the user still reaches the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _later();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFF1B2733)),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.08),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.system_update_alt_rounded,
                          color: _accent,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: _text(size: 21, weight: FontWeight.w900),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: _text(size: 13, color: _muted, height: 1.7),
                        ),
                      ],
                      if (forced) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C141C),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF243140),
                            ),
                          ),
                          child: Text(
                            'برای ادامهٔ استفاده از برنامه، نصب نسخهٔ جدید الزامی است.',
                            textAlign: TextAlign.center,
                            style: _text(size: 12, color: _muted, height: 1.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: const Color(0xFF04110C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _openDownload(context),
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: Text(
                            'دانلود و به‌روزرسانی',
                            style: _text(
                              size: 15,
                              weight: FontWeight.w800,
                              color: const Color(0xFF04110C),
                            ),
                          ),
                        ),
                      ),
                      if (!forced) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _later,
                          child: Text(
                            'بعداً',
                            style: _text(
                              size: 13,
                              weight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
