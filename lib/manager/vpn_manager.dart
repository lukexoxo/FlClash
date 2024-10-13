import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/function.dart';

/// 当 Android 修改 VPN 配置后，提示用户重启VPN
/// Android提示：重启VPN后改变生效
class VpnManager extends StatefulWidget {
  final Widget child;

  const VpnManager({
    super.key,
    required this.child,
  });

  @override
  State<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends State<VpnManager> {
  Function? vpnTipDebounce;

  showTip() {
    vpnTipDebounce ??= debounce<Function()>(() async {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final appFlowingState = globalState.appController.appFlowingState;
        if (appFlowingState.isStart) {
          globalState.showSnackBar(
            context,
            message: appLocalizations.vpnTip,
          );
        }
      });
    });
    vpnTipDebounce!();
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<Config, ClashConfig, VPNState>(
      selector: (_, config, clashConfig) => VPNState(
        accessControl: config.accessControl,
        vpnProps: config.vpnProps,
        stack: clashConfig.tun.stack,
      ),
      shouldRebuild: (prev, next) {
        if (prev != next) {
          showTip();
        }
        return prev != next;
      },
      builder: (_, __, child) {
        return child!;
      },
      child: widget.child,
    );
  }
}
