class ChannelModel {
  String? result;
  String? message;
  List<ChannelModelData>? data;
  Setting? setting;

  ChannelModel({this.result, this.message, this.data, this.setting});

  ChannelModel.fromJson(Map<String, dynamic> json) {
    result = json['result'];
    message = json['message'];
    setting =
        json['setting'] != null ? Setting.fromJson(json['setting']) : null;
    if (json['data'] != null) {
      data = <ChannelModelData>[];
      json['data'].forEach((v) {
        data!.add(ChannelModelData.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['result'] = result;
    data['message'] = message;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Setting {
  String? version;
  String? updateTitle;
  String? updateDesc;
  String? udateUrl;
  bool? shouldUpdate;

  Setting(
      {this.version,
      this.updateTitle,
      this.updateDesc,
      this.udateUrl,
      this.shouldUpdate});

  Setting.fromJson(Map<String, dynamic> json) {
    version = json['version'];
    updateTitle = json['update_title'];
    updateDesc = json['update_desc'];
    udateUrl = json['update_url'];
    shouldUpdate = bool.parse(json['should_update'].toString());
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['version'] = version;
    data['update_title'] = updateTitle;
    data['update_desc'] = updateDesc;
    data['update_url'] = udateUrl;
    data['should_update'] = shouldUpdate;
    return data;
  }
}

class ChannelModelData {
  String? id;
  String? messageId;
  String? channelId;
  String? links;
  String? time;
  String? photoLink;
  String? title;

  ChannelModelData(
      {this.id,
      this.messageId,
      this.channelId,
      this.links,
      this.time,
      this.photoLink,
      this.title});

  ChannelModelData.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    messageId = json['message_id'];
    channelId = json['channel_id'];
    links = json['links'];
    time = json['time'];
    photoLink = json['photo_link'];
    title = json['title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['message_id'] = messageId;
    data['channel_id'] = channelId;
    data['links'] = links;
    data['time'] = time;
    data['photo_link'] = photoLink;
    data['title'] = title;
    return data;
  }
}
