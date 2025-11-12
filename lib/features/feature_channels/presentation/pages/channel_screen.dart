import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../../core/utils/page_status.dart';
import '../../../../core/widgets/mytext.dart';
import '../controllers/channel_controller.dart';
import '../widgets/proxy_item.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final channelController = Get.put(ChannelController());

  double messgaeRadios = 15;

  @override
  void initState() {
    super.initState();
    // adController.adInitilzer?.loadOpenAd();
    // adController.adInitilzer?.showOpenAd();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF03346E),
        title: const MyText(
            txt: "پروکسی من",
            fontWeight: FontWeight.bold,
            size: 18,
            color: Colors.white),
        centerTitle: true,
        actions: const [],
      ),
      backgroundColor: const Color(0xFF021526),
      // bottomNavigationBar: adController.adInitilzer?.showBanner(),
      body: GetBuilder<ChannelController>(builder: (controller) {
        if (controller.channelStatus == PageStatus.loading) {
          return Shimmer.fromColors(
              baseColor: Colors.white10,
              highlightColor: Colors.white24,
              child: ListView.builder(itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    height: 80,
                    width: size.width - 20,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                );
              }));
        }
        if (controller.channelStatus == PageStatus.error) {
          return const Center(
            child: Text("Error"),
          );
        }

        return Column(
          children: [
            const SizedBox(height: 5),
            if (channelController.channelModel?.setting?.shouldUpdate == true)
              Directionality(
                textDirection: TextDirection.rtl,
                child: Container(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B99C2),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  width: double.infinity,
                  // height: 100,
                  child: Column(
                    children: [
                      const Gap(5),
                      MyText(
                        txt: channelController
                                .channelModel?.setting?.updateTitle ??
                            "",
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      // const Gap(5),
                      MyText(
                          color: Colors.white,
                          txt: channelController
                                  .channelModel?.setting?.updateDesc ??
                              ""),
                      TextButton.icon(
                          onPressed: () {
                            launchUrlString(channelController
                                    .channelModel?.setting?.udateUrl ??
                                "https://play.google.com");
                          },
                          icon: const Icon(Iconsax.arrow_down_24),
                          label: const MyText(
                            txt: 'نصب',
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ))
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SmartRefresher(
                controller: controller.refreshController,
                enablePullDown: true,
                enablePullUp: true,
                // header: WaterDropHeader(),
                onRefresh: () async {
                  controller.getChannel(false);
                  controller.refreshController.refreshCompleted();
                },
                onLoading: () async {
                  controller.getChannel(true);
                  controller.refreshController.loadComplete();
                },
                child: ListView.builder(
                  // revers
                  itemCount: channelController.channelModel?.data?.length ?? 0,
                  itemBuilder: (context, index) {
                    String ping = "0";
                    if (controller.pingList.length > index) {
                      ping = controller.pingList[index];
                    } else {
                      ping = "0";
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child:
                          ProxyItemWidget(size: size, ping: ping, index: index),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
