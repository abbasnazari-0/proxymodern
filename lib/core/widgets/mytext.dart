import 'package:flutter/material.dart';

class MyText extends StatelessWidget {
  const MyText(
      {Key? key,
      this.txt = '',
      this.color,
      this.textAlign = TextAlign.justify,
      this.size = 15,
      this.fontWeight,
      this.maxLine,
      this.overflow})
      : super(key: key);
  final String txt;
  final Color? color;
  final TextAlign textAlign;
  final double size;
  final FontWeight? fontWeight;
  final int? maxLine;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      txt,
      style: TextStyle(
          fontFamily: 'vazir',
          color: color ?? Colors.black,
          fontSize: size,
          fontWeight: fontWeight),
      textAlign: textAlign,
      maxLines: maxLine,
      overflow: overflow,
    );
  }
}
