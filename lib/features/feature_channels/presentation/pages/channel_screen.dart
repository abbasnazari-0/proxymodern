import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../../core/utils/constans.dart';
import '../../../../core/utils/data_extractor.dart';
import '../../../../core/utils/get_storage_data.dart';
import '../../../../core/utils/page_status.dart';
import '../../../../core/utils/relay_ads_service.dart';
import '../controllers/channel_controller.dart';
import '../widgets/app_about_sheet.dart';
import '../widgets/legacy_mode_toggle.dart';
import '../widgets/proxy_found_sheet.dart';
import 'legacy_channel_view.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  bool _legacyListMode = false;

  @override
  void initState() {
    super.initState();
    Get.put(ChannelController());
    final saved = GetStorageData.getData(storageKeyLegacyListMode);
    _legacyListMode = saved == true;
  }

  Future<void> _setLegacyListMode(bool enabled) async {
    await GetStorageData.writeData(storageKeyLegacyListMode, enabled);
    setState(() => _legacyListMode = enabled);
    if (enabled) {
      final controller = Get.find<ChannelController>();
      if (controller.channelStatus == PageStatus.success &&
          controller.channelModel?.data != null) {
        controller.startPingList();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_legacyListMode) {
      return LegacyChannelView(
        legacyEnabled: _legacyListMode,
        onLegacyChanged: _setLegacyListMode,
      );
    }
    return _ModernChannelView(
      legacyEnabled: _legacyListMode,
      onLegacyChanged: _setLegacyListMode,
    );
  }
}

class _ModernChannelView extends StatefulWidget {
  const _ModernChannelView({
    required this.legacyEnabled,
    required this.onLegacyChanged,
  });

  final bool legacyEnabled;
  final ValueChanged<bool> onLegacyChanged;

  @override
  State<_ModernChannelView> createState() => _ModernChannelViewState();
}

class _ModernChannelViewState extends State<_ModernChannelView>
    with SingleTickerProviderStateMixin {
  ChannelController get channelController => Get.find<ChannelController>();
  late final AnimationController _pulse;

  FindPhase get _phase => channelController.findPhase;
  int? get _index => channelController.selectedIndex;

  static const _bg = Color(0xFF081016);
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _find({int? exclude}) async {
    final c = channelController;
    if (c.findPhase == FindPhase.searching) return;

    if (!(c.channelModel?.data?.isNotEmpty ?? false)) {
      await c.waitForInitialLoad();
      if (!(c.channelModel?.data?.isNotEmpty ?? false)) {
        final ok = await c.getChannel(false);
        if (!ok) {
          _showIssue(title: c.errorTitle, message: c.errorMessage);
          return;
        }
      }
    }

    HapticFeedback.mediumImpact();

    final index = await c.findWorkingProxy(excludeIndex: exclude);
    if (!mounted) return;

    if (index == null) {
      if (exclude != null && c.selectedIndex != null) {
        c.findPhase = FindPhase.found;
        c.update();
      }
      _showIssue(title: c.errorTitle, message: c.errorMessage);
      return;
    }

    final item = c.channelModel?.data?[index];
    final link = item?.links ?? "";
    if (link.isEmpty) {
      _showIssue(
        title: "لینک پروکسی نیست",
        message: "این سرور لینک معتبر ندارد.",
      );
      return;
    }

    // Proxy found successfully → show one interstitial before the result.
    await RelayAdsService.instance.showOneAd();
    if (!mounted) return;

    await ProxyFoundSheet.show(
      link: link,
      caption: item?.title?.trim().isNotEmpty == true
          ? item!.title!.trim()
          : "پروکسی آماده اتصال است",
    );
  }

  String? get _link {
    if (_index == null) return null;
    return channelController.channelModel?.data?[_index!].links;
  }

  String get _ping {
    if (_index == null) return "—";
    if (channelController.pingList.length <= _index!) return "—";
    final value = int.tryParse(channelController.pingList[_index!]) ?? -1;
    if (value <= 0) return "—";
    final result = channelController.pingResults[_index!];
    if (result != null && result.isAlive && result.jitter >= 0) {
      return "$value ms · نوسان ${result.jitter}";
    }
    return "$value ms";
  }

  int get _bars {
    if (_index == null) return 0;
    if (channelController.pingList.length <= _index!) return 0;
    final value = int.tryParse(channelController.pingList[_index!]) ?? -1;
    if (value <= 0) return 0;
    if (value <= 120) return 4;
    if (value <= 250) return 3;
    if (value <= 450) return 2;
    return 1;
  }

  String get _location {
    final item = _index == null
        ? null
        : channelController.channelModel?.data?[_index!];
    final title = item?.title?.trim() ?? "";
    if (title.isNotEmpty) return title;
    final host = _link == null ? null : DataExtractor.queryParam(_link!, "server");
    return (host == null || host.isEmpty) ? "—" : host;
  }

  String get _protocol {
    final link = _link;
    if (link == null || link.isEmpty) return "—";
    return DataExtractor.protocolLabel(link);
  }

  String get _endpoint {
    final link = _link;
    if (link == null) return "—";
    final host = DataExtractor.queryParam(link, "server");
    final port = DataExtractor.queryParam(link, "port");
    if (host == null || port == null || host.isEmpty || port.isEmpty) {
      return "—";
    }
    return "$host:$port";
  }

  String get _headline {
    final c = channelController;
    switch (_phase) {
      case FindPhase.searching:
        return "دارم پیدا می‌کنم";
      case FindPhase.found:
        return "پیدا شد";
      case FindPhase.failed:
        return c.errorTitle;
      case FindPhase.idle:
        if (c.channelStatus == PageStatus.loading) {
          return "در حال آماده‌سازی";
        }
        if (c.channelStatus == PageStatus.error ||
            c.channelStatus == PageStatus.empty) {
          return c.errorTitle;
        }
        return "پروکسی تلگرام";
    }
  }

  String get _subtitle {
    final c = channelController;
    switch (_phase) {
      case FindPhase.searching:
        return "چند ثانیه طول می‌کشد، بعد تلگرام باز می‌شود";
      case FindPhase.found:
        return "پروکسی آماده است. از شیت پایین وصل شو";
      case FindPhase.failed:
        return c.errorMessage;
      case FindPhase.idle:
        if (c.channelStatus == PageStatus.loading) {
          return "لیست سرورها در حال دریافت است...";
        }
        if (c.channelStatus == PageStatus.error ||
            c.channelStatus == PageStatus.empty) {
          return c.errorMessage;
        }
        return "دکمه را بزن تا پیدا شود و تلگرام باز شود";
    }
  }

  bool get _showRetry {
    final c = channelController;
    if (_phase == FindPhase.searching) return false;
    if (_phase == FindPhase.failed) return true;
    if (_phase == FindPhase.idle &&
        (c.channelStatus == PageStatus.error ||
            c.channelStatus == PageStatus.empty)) {
      return true;
    }
    return false;
  }

  void _showIssue({required String title, required String message}) {
    Get.snackbar(
      "",
      "",
      backgroundColor: _card,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
      titleText: Text(
        title,
        textAlign: TextAlign.center,
        style: _text(size: 14, weight: FontWeight.w700),
      ),
      messageText: Text(
        message,
        textAlign: TextAlign.center,
        style: _text(size: 12, color: _muted, height: 1.4),
      ),
    );
  }

  Future<void> _retryLoad() async {
    HapticFeedback.lightImpact();
    channelController.findPhase = FindPhase.idle;
    channelController.update();
    final ok = await channelController.getChannel(false);
    if (!mounted) return;
    if (!ok) {
      _showIssue(
        title: channelController.errorTitle,
        message: channelController.errorMessage,
      );
    }
  }

  String get _buttonLabel {
    if (channelController.channelStatus == PageStatus.loading &&
        _phase != FindPhase.searching) {
      return "آماده‌سازی";
    }
    switch (_phase) {
      case FindPhase.searching:
        return "صبر کن";
      case FindPhase.found:
        return "پیدا شد";
      case FindPhase.failed:
        return "دوباره";
      case FindPhase.idle:
        return "پیدا کن";
    }
  }

  String get _statusLabel {
    switch (_phase) {
      case FindPhase.searching:
        return "در حال جستجو";
      case FindPhase.found:
        return "آماده اتصال";
      case FindPhase.failed:
        return "پیدا نشد";
      case FindPhase.idle:
        return "منتظر";
    }
  }

  Color get _statusColor {
    final c = channelController;
    switch (_phase) {
      case FindPhase.found:
        return _accent;
      case FindPhase.failed:
        return const Color(0xFFFF6B6B);
      case FindPhase.searching:
        return const Color(0xFF8FD4FF);
      case FindPhase.idle:
        if (c.channelStatus == PageStatus.error ||
            c.channelStatus == PageStatus.empty) {
          return const Color(0xFFFF8A8A);
        }
        if (c.channelStatus == PageStatus.loading) {
          return const Color(0xFF8FD4FF);
        }
        return _muted;
    }
  }

  Future<void> _copyLink() async {
    final link = _link;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    Get.snackbar(
      "",
      "",
      backgroundColor: _card,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      titleText: Text(
        "لینک کپی شد",
        textAlign: TextAlign.center,
        style: _text(size: 14),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  void _openAbout() {
    AppAboutSheet.show(setting: channelController.channelModel?.setting);
  }

  TextStyle _text({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = Colors.white,
    double? height,
  }) {
    return TextStyle(
      fontFamily: "vazir",
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _bg,
          body: GetBuilder<ChannelController>(
            builder: (controller) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                  child: Column(
                    children: [
                      _header(controller.channelModel?.setting?.shouldUpdate == true),
                      Expanded(child: _buttonSlot()),
                      _statusBlock(),
                      const SizedBox(height: 12),
                      _detailsCard(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(bool hasUpdate) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("سوپر ", style: _text(size: 20, weight: FontWeight.w700)),
                    Text(
                      "پروکسی",
                      style: _text(size: 20, weight: FontWeight.w700, color: _accent),
                    ),
                  ],
                ),
                Text(
                  "وصل شدن داخل تلگرام",
                  style: _text(size: 11, color: _muted),
                ),
              ],
            ),
          ),
          LegacyModeToggle(
            enabled: widget.legacyEnabled,
            onChanged: widget.onLegacyChanged,
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _openAbout,
            icon: Badge(
              isLabelVisible: hasUpdate,
              smallSize: 7,
              backgroundColor: _accent,
              child: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buttonSlot() {
    final searching = _phase == FindPhase.searching;
    final booting = channelController.channelStatus == PageStatus.loading &&
        _phase != FindPhase.searching;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth * 0.62, constraints.maxHeight);
        return Center(
          child: GestureDetector(
            onTap: searching || booting ? null : () => _find(),
            child: SizedBox(
              width: side,
              height: side,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final turn =
                      searching || booting ? _pulse.value : -0.25;
                  final strength = switch (_phase) {
                    FindPhase.found => 1.0,
                    FindPhase.searching => 0.95,
                    _ => booting ? 0.75 : 0.55,
                  };
                  return CustomPaint(
                    painter: _RingPainter(rotation: turn, strength: strength),
                    child: Center(
                      child: Container(
                        width: side * 0.74,
                        height: side * 0.74,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0C141C),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(
                                alpha: _phase == FindPhase.found ? 0.22 : 0.08,
                              ),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (searching || booting)
                              SizedBox(
                                width: side * 0.16,
                                height: side * 0.16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              )
                            else
                              Icon(
                                Icons.power_settings_new_rounded,
                                color: Colors.white,
                                size: side * 0.2,
                              ),
                            SizedBox(height: side * 0.02),
                            Text(
                              _buttonLabel,
                              style: _text(size: 13, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusBlock() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(_headline, style: _text(size: 17, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _subtitle,
          textAlign: TextAlign.center,
          maxLines: 3,
          style: _text(size: 12, color: _muted, height: 1.4),
        ),
        if (_showRetry) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _phase == FindPhase.failed ? () => _find() : _retryLoad,
            child: Text(
              _phase == FindPhase.failed ? "تلاش دوباره" : "دریافت مجدد لیست",
              style: _text(size: 13, weight: FontWeight.w700, color: _accent),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text("جزئیات", style: _text(size: 13, weight: FontWeight.w700)),
              const Spacer(),
              if (_phase == FindPhase.found)
                GestureDetector(
                  onTap: () => _find(exclude: _index),
                  child: Text(
                    "یکی دیگر",
                    style: _text(size: 12, weight: FontWeight.w700, color: _accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _line("نام", _location),
          _line("نوع", _protocol),
          _line(
            "آدرس",
            _endpoint,
            ltr: true,
            trailing: _link == null
                ? null
                : GestureDetector(
                    onTap: _copyLink,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.copy_rounded, size: 15, color: _muted),
                    ),
                  ),
          ),
          _line(
            "پاسخ",
            _ping,
            ltr: true,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SignalBars(level: _bars),
            ),
          ),
          _line("وضعیت", _statusLabel, valueColor: _statusColor, last: true),
        ],
      ),
    );
  }

  Widget _line(
    String label,
    String value, {
    bool ltr = false,
    Color? valueColor,
    Widget? trailing,
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFF1C2833), width: 1),
              ),
      ),
      child: Row(
        children: [
          Text(label, style: _text(size: 12, color: _muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(
                  size: 13,
                  weight: FontWeight.w600,
                  color: valueColor ?? Colors.white,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.rotation, required this.strength});

  final double rotation;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF3DDC97).withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, base);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        transform: GradientRotation(rotation * math.pi * 2),
        colors: [
          const Color(0xFF3DDC97).withValues(alpha: 0),
          const Color(0xFF3DDC97).withValues(alpha: strength),
          const Color(0xFFD8FFEF).withValues(alpha: strength),
          const Color(0xFF3DDC97).withValues(alpha: 0),
        ],
        stops: const [0.05, 0.42, 0.55, 0.82],
      ).createShader(Offset.zero & size);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 2,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.strength != strength;
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final on = index < level;
        return Container(
          width: 3,
          height: 5 + index * 2.5,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF3DDC97) : const Color(0xFF243140),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
