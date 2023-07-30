import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/ad/ad_controller.dart';
import '../../../../core/utils/page_status.dart';
import '../../../../core/widgets/mytext.dart';
import '../controllers/channel_controller.dart';
import '../widgets/proxy_item.dart';

class ChannelScreen extends StatefulWidget {
  ChannelScreen({super.key});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final adController = Get.put(AdController());

  final channelController = Get.put(ChannelController());

  double messgaeRadios = 15;

  @override
  void initState() {
    // TODO: implement initState

    adController.adInitilzer?.loadRewarded();
    // adController.adInitilzer?.loadBanner();
    // adController.adInitilzer?.loadOpenAd();
    // adController.adInitilzer?.showOpenAd();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: const MyText(
            txt: "پروکسی من",
            fontWeight: FontWeight.bold,
            size: 18,
            color: Colors.white),
        centerTitle: true,
        actions: [
          // IconButton(
          //     onPressed: () {
          //       Get.dialog(
          //         Material(
          //           color: Colors.transparent,
          //           child: Container(
          //             width: 40,
          //             height: 40,
          //             decoration: BoxDecoration(
          //                 color: const Color(0xFF222222),
          //                 borderRadius: BorderRadius.circular(20)),
          //             margin: const EdgeInsets.symmetric(
          //                 horizontal: 40, vertical: 120),
          //             child: Column(
          //               children: [
          //                 Row(
          //                   mainAxisAlignment: MainAxisAlignment.center,
          //                   children: [
          //                     IconButton(
          //                         onPressed: () {
          //                           Get.back();
          //                         },
          //                         icon: const Icon(
          //                           Iconsax.close_circle,
          //                           color: Colors.white,
          //                         )),
          //                     const SizedBox(width: 10),
          //                   ],
          //                 ),
          //                 const MyText(
          //                   txt: "راهنمای پروکسی من",
          //                   textAlign: TextAlign.center,
          //                   fontWeight: FontWeight.bold,
          //                   size: 18,
          //                   color: Colors.white,
          //                 )
          //               ],
          //             ),
          //           ),
          //         ),
          //       );
          //     },
          //     icon: const Icon(
          //       Iconsax.information5,
          //       color: Colors.white,
          //     )),
        ],
      ),
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

        return SmartRefresher(
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
            shrinkWrap: true,
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
                child: ProxyItemWidget(size: size, ping: ping, index: index),
              );
            },
          ),
        );
      }),
    );
  }
}
