import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

/// src是 base64 编码的图片
/// 或者是网络图片地址
/// 如果src为空，显示默认图标
class CommonIcon extends StatelessWidget {
  final String src;
  final double size;

  const CommonIcon({
    super.key,
    required this.src,
    required this.size,
  });

  Widget _defaultIcon() {
    return Icon(
      IconsExt.target,
      size: size,
    );
  }

  Widget _buildIcon() {
    if (src.isEmpty) {
      return _defaultIcon();
    }
    final base64 = src.getBase64;
    if (base64 != null) {
      return Image.memory(
        base64,
        gaplessPlayback: true,
        errorBuilder: (_, error, ___) {
          return _defaultIcon();
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: src,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      errorWidget: (_, __, ___) => _defaultIcon(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: _buildIcon(),
    );
  }
}
