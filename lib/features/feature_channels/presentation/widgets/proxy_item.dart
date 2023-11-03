import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:proxymodern/core/widgets/mytext.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/ad/ad_controller.dart';
import '../../../../core/utils/data_extractor.dart';
import '../controllers/channel_controller.dart';

class ProxyItemWidget extends StatefulWidget {
  ProxyItemWidget(
      {super.key,
      required this.size,
      required this.ping,
      required this.index,
      this.clickable = true});

  final Size size;
  final String ping;
  final int index;
  final bool clickable;

  @override
  State<ProxyItemWidget> createState() => _ProxyItemWidgetState();
}

class _ProxyItemWidgetState extends State<ProxyItemWidget> {
  final controller = Get.find<ChannelController>();
  String? flag;
  final adController = Get.find<AdController>();

  // @override
  // void initState() {
  //   // TODO: implement initState
  //   super.initState();
  //   getCountryCode();
  // }

  // getCountryCode() async {
  //   flag = await controller.getCountryFlag(DataExtractor.extractFromLink(
  //       "${controller.channelModel?.data?[widget.index].links}", "host"));
  // }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (!widget.clickable) return;
        Get.bottomSheet(
          GetBuilder<AdController>(initState: (state) {
            state.controller?.adInitilzer?.loadRewarded();
          }, dispose: (state) {
            state.controller?.adInitilzer?.disposeRewarded();
          }, builder: (context) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                // color:  Color,
                borderRadius: BorderRadius.circular(10),
              ),
              height: widget.size.height * 0.5,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                          onPressed: () {
                            Get.back();
                          },
                          icon: const Icon(
                            Iconsax.close_circle,
                            color: Colors.white,
                          )),
                      const SizedBox(width: 10),
                    ],
                  ),
                  ProxyItemWidget(
                      size: widget.size,
                      ping: widget.ping,
                      index: widget.index,
                      clickable: false),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      if (adController.adInitilzer?.hasFullScreenAd == false) {
                        Get.snackbar("", "",
                            titleText: const MyText(
                              txt: "لطفا صبر کنید",
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              size: 16,
                              textAlign: TextAlign.center,
                            ));
                        return;
                      }
                      if (Platform.isAndroid || Platform.isIOS) {
                        // await adController.adInitilzer?.loadRewarded();
                        await adController.adInitilzer
                            ?.showRewarded()
                            .then((value) async {
                          if (value == 1 || value == 0) {
                            await Future.delayed(
                                const Duration(milliseconds: 1000), () async {
                              await Share.share(
                                  "${controller.channelModel?.data?[widget.index].links}");
                            });
                          }
                        });
                      }
                    },
                    child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF293A80),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: double.infinity,
                        height: 60,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MyText(
                              txt: "اشتراک گذاری پروکسی",
                              size: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                            Icon(
                              Icons.share_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(width: 10),
                          ],
                        )),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      bool result = false;
                      if (adController.adInitilzer?.hasFullScreenAd == false) {
                        Get.snackbar("", "",
                            titleText: const MyText(
                              txt: "لطفا صبر کنید",
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              size: 16,
                              textAlign: TextAlign.center,
                            ));
                        return;
                      }
                      if (Platform.isAndroid || Platform.isIOS) {
                        // await adController.adInitilzer?.loadRewarded();
                        await adController.adInitilzer
                            ?.showRewarded()
                            .then((value) async {
                          if (value == 1 || value == 0) {
                            await Future.delayed(
                                const Duration(milliseconds: 3000), () async {
                              result = await DataExtractor.launchUrl(controller
                                      .channelModel
                                      ?.data?[widget.index]
                                      .links ??
                                  "");
                            });
                          }
                        });

                        if (!result) {
                          Get.close(0);
                          Get.bottomSheet(
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF222222),
                                // color:  Color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              height: widget.size.height * 0.5,
                              width: double.infinity,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                            onPressed: () {
                                              Get.back();
                                            },
                                            icon: const Icon(
                                              Iconsax.close_circle,
                                              color: Colors.white,
                                            )),
                                        const SizedBox(width: 10),
                                      ],
                                    ),
                                    const MyText(
                                      txt:
                                          "خطا در وصل شدن به پروکسی به صورت خودکار",
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      size: 16,
                                    ),
                                    const SizedBox(height: 10.0),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 10),
                                      child: MyText(
                                        txt:
                                            "نتواستیم بصورت خودکار به پروکسی وصل شویم لطفا مرحله آسان زیر را انجام دهید"
                                            "\n\n"
                                            "لینک زیر را کپی کنید",
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        size: 14,
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    const SizedBox(height: 5.0),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      child: SizedBox(
                                        height: 60,
                                        child: TextField(
                                          controller: TextEditingController(
                                              text:
                                                  "${controller.channelModel?.data?[widget.index].links}"),
                                          style: const TextStyle(
                                              color: Colors.white),
                                          decoration: InputDecoration(
                                              border: const OutlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: Colors.teal)),
                                              suffix: IconButton(
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                        ClipboardData(
                                                            text:
                                                                "${controller.channelModel?.data?[widget.index].links}"));

                                                    Get.snackbar("", "",
                                                        titleText: const MyText(
                                                          txt:
                                                              "با موفقیت کپی شد",
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          size: 16,
                                                          textAlign:
                                                              TextAlign.center,
                                                        ));
                                                  },
                                                  icon: const Icon(
                                                    Iconsax.copy,
                                                    color: Colors.white,
                                                  ))),
                                        ),
                                      ),
                                    ),
                                    const Divider(
                                      color: Colors.white10,
                                      thickness: 0.4,
                                    ),
                                    const SizedBox(height: 5.0),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 10),
                                      child: MyText(
                                        txt:
                                            "به تلگرام خود رفته و روی چت Saved Message کلیک کرده و در چت خود Paste نمایید \nارسال کنید\nوقتی ارسال شد روی لینک زده و وصل خواهید شد\n😄😁",
                                        textAlign: TextAlign.right,
                                        color: Colors.white,
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                            backgroundColor: Colors.white,
                            // backgroundColor: Colors.red,
                            elevation: 1,
                            enableDrag: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF39422),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: double.infinity,
                        height: 60,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MyText(
                              txt: "وصل شدن سریع",
                              size: 18,
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                            ),
                            Icon(
                              Icons.shortcut_rounded,
                              color: Colors.black,
                            ),
                            SizedBox(width: 10),
                          ],
                        )),
                  ),
                  const SizedBox(height: 10),
                  // GetBuilder<AdController>(builder: (controller) {
                  //   return controller.adInitilzer?.showBanner() ?? Container();
                  // }),
                ],
              ),
            );
          }),
          backgroundColor: Colors.white,
          // backgroundColor: Colors.red,
          elevation: 1,
          enableDrag: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
        // print("ddsdsds ${widget.index}");
      },
      child: Container(
        decoration: BoxDecoration(
          // border: Border.all(color: Color(0xFF2C394B)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withAlpha(10),
              blurRadius: 0,
              offset: const Offset(2, 1),
            ),
          ],
          borderRadius: BorderRadius.circular(10),
        ),
        // height: 95,
        width: widget.size.width - 20,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              height: 10,
            ),
            Row(children: [
              const SizedBox(width: 10),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(
                      controller.channelModel?.data?[widget.index].photoLink ??
                          "",
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // const Icon(Iconsax.link4, color: Colors.white),
              // const SizedBox(width: 10),

              // const SizedBox(width: 10),
              // divider
              VerticalDivider(
                color: Colors.white.withAlpha(20),
                thickness: 1,
                width: 1,
                indent: 20,
                endIndent: 20,
              ),

              const SizedBox(width: 10),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MyText(
                    txt: controller.channelModel?.data?[widget.index].title ??
                        "",
                    size: 14,
                    color: Colors.white.withAlpha(100),
                    fontWeight: FontWeight.w100,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  MyText(
                    txt: DataExtractor.extractFromLink(
                                    "${controller.channelModel?.data?[widget.index].links}",
                                    "host")
                                .length >
                            20
                        ? '${DataExtractor.extractFromLink("${controller.channelModel?.data?[widget.index].links}", "host").substring(0, 20)}...'
                        : DataExtractor.extractFromLink(
                            "${controller.channelModel?.data?[widget.index].links}",
                            "host"),
                    size: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                  // last update
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 20,
                    child: Row(children: [
                      const SizedBox(width: 10),
                      MyText(
                        txt: "Last Update",
                        size: 10,
                        color: Colors.white.withAlpha(100),
                        fontWeight: FontWeight.w100,
                      ),
                      const SizedBox(width: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        child: MyText(
                          txt: DataExtractor.formatDateTime(
                              controller
                                      .channelModel?.data?[widget.index].time ??
                                  "",
                              format: "HH:mm"),
                          size: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      // const Spacer(),
                      // const SizedBox(width: 10),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ),

              const Spacer(),
              // const SizedBox(width: 10),
              // divider
              VerticalDivider(
                color: Colors.white.withAlpha(20),
                thickness: 1,
                width: 1,
                indent: 20,
                endIndent: 20,
              ),

              const SizedBox(width: 10),

              // ping
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MyText(
                    txt: "Ping",
                    size: 14,
                    color: Colors.white.withAlpha(100),
                    fontWeight: FontWeight.w100,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      MyText(
                        txt: widget.ping,
                        size: 16,
                        color: DataExtractor.pingColor((widget.ping)),
                        fontWeight: FontWeight.w900,
                      ),
                      const SizedBox(width: 5),
                      const MyText(
                        txt: "ms",
                        size: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(width: 20),
            ]),
          ],
        ),
      ),
    );
  }
}
