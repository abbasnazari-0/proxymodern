import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../../core/utils/page_status.dart';
import '../controllers/channel_controller.dart';
import '../widgets/legacy_mode_toggle.dart';
import '../widgets/proxy_item.dart';

class LegacyChannelView extends StatefulWidget {
  const LegacyChannelView({
    super.key,
    required this.legacyEnabled,
    required this.onLegacyChanged,
  });

  final bool legacyEnabled;
  final ValueChanged<bool> onLegacyChanged;

  @override
  State<LegacyChannelView> createState() => _LegacyChannelViewState();
}

class _LegacyChannelViewState extends State<LegacyChannelView> {
  final channelController = Get.find<ChannelController>();
  bool _pingStarted = false;

  static const _bg = Color(0xFF081016);
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  @override
  void initState() {
    super.initState();
    _maybeStartPing();
  }

  void _maybeStartPing() {
    if (_pingStarted) return;
    if (channelController.channelStatus != PageStatus.success) return;
    if (channelController.channelModel?.data == null) return;
    _pingStarted = true;
    channelController.startPingList();
  }

  void _showLoadIssue(ChannelController controller) {
    Get.snackbar(
      "",
      "",
      backgroundColor: _card,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
      titleText: Text(
        controller.errorTitle,
        textAlign: TextAlign.center,
        style: _text(size: 14, weight: FontWeight.w700),
      ),
      messageText: Text(
        controller.errorMessage,
        textAlign: TextAlign.center,
        style: _text(size: 12, color: _muted, height: 1.4),
      ),
    );
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
    final size = MediaQuery.of(context).size;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: GetBuilder<ChannelController>(builder: (controller) {
              _maybeStartPing();
              final count = controller.channelModel?.data?.length ?? 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "لیست پروکسی",
                                style: _text(size: 20, weight: FontWeight.w700),
                              ),
                              Text(
                                _subtitleFor(controller, count),
                                style: _text(size: 11, color: _muted),
                              ),
                            ],
                          ),
                        ),
                        LegacyModeToggle(
                          enabled: widget.legacyEnabled,
                          onChanged: widget.onLegacyChanged,
                        ),
                      ],
                    ),
                  ),
                  if (controller.channelModel?.setting?.shouldUpdate == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _updateBanner(),
                    ),
                  Expanded(child: _body(controller, size)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _updateBanner() {
    final setting = channelController.channelModel?.setting;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  setting?.updateTitle ?? "نسخه جدید",
                  style: _text(size: 13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  setting?.updateDesc ?? "",
                  style: _text(size: 11, color: _muted, height: 1.4),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              launchUrlString(setting?.udateUrl ?? "https://play.google.com");
            },
            child: Text(
              "نصب",
              style: _text(size: 12, weight: FontWeight.w700, color: _accent),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitleFor(ChannelController controller, int count) {
    if (controller.channelStatus == PageStatus.loading) {
      return "در حال دریافت لیست...";
    }
    if (controller.channelStatus == PageStatus.error) {
      return "خطا در بارگذاری";
    }
    if (controller.channelStatus == PageStatus.empty) {
      return "فعلاً سروری نیست";
    }
    if (count == 0) return "در حال آماده‌سازی";
    return "$count سرور برای انتخاب";
  }

  Widget _body(ChannelController controller, Size size) {
    if (controller.channelStatus == PageStatus.loading) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFF141C26),
        highlightColor: const Color(0xFF1E2A38),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: 7,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => Container(
            height: 88,
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (controller.channelStatus == PageStatus.error ||
        controller.channelStatus == PageStatus.empty) {
      return _errorOrEmpty(controller);
    }

    return SmartRefresher(
      controller: controller.refreshController,
      enablePullDown: true,
      enablePullUp: true,
      onRefresh: () async {
        _pingStarted = false;
        final ok = await controller.getChannel(false);
        if (ok) {
          _maybeStartPing();
        } else if (controller.channelStatus == PageStatus.success) {
          _showLoadIssue(controller);
        }
        controller.refreshController.refreshCompleted();
      },
      onLoading: () async {
        final ok = await controller.getChannel(true);
        if (ok) {
          _pingStarted = false;
          _maybeStartPing();
          controller.refreshController.loadComplete();
        } else {
          _showLoadIssue(controller);
          controller.refreshController.loadFailed();
        }
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: channelController.channelModel?.data?.length ?? 0,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final ping = controller.pingList.length > index
              ? controller.pingList[index]
              : "0";
          return _StaggeredListItem(
            index: index,
            revealToken: controller.listRevealToken,
            child: ProxyItemWidget(
              size: size,
              ping: ping,
              index: index,
            ),
          );
        },
      ),
    );
  }

  Widget _errorOrEmpty(ChannelController controller) {
    final isEmpty = controller.channelStatus == PageStatus.empty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEmpty ? Icons.inbox_outlined : Icons.wifi_off_rounded,
              color: isEmpty ? _muted : const Color(0xFFFF8A8A),
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              controller.errorTitle,
              textAlign: TextAlign.center,
              style: _text(size: 16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              controller.errorMessage,
              textAlign: TextAlign.center,
              style: _text(size: 13, color: _muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF062018),
              ),
              onPressed: () => controller.getChannel(false),
              child: Text(
                isEmpty ? "بررسی دوباره" : "تلاش دوباره",
                style: _text(
                  size: 14,
                  weight: FontWeight.w700,
                  color: const Color(0xFF062018),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaggeredListItem extends StatefulWidget {
  const _StaggeredListItem({
    required this.index,
    required this.revealToken,
    required this.child,
  });

  final int index;
  final int revealToken;
  final Widget child;

  @override
  State<_StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<_StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _play();
  }

  @override
  void didUpdateWidget(covariant _StaggeredListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealToken != widget.revealToken) {
      _controller.reset();
      _play();
    }
  }

  void _play() {
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 14));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}
