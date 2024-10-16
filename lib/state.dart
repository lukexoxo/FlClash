import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'models/models.dart';
import 'common/common.dart';

/// 全局单例对象
///
/// timer                 每秒执行一次updateFunctionLists: updateTraffic updateRunTime
/// isVpnService          是否启动Android VPN服务，启动VPN服务和流量统计磁贴
/// packageInfo           包信息
/// pageController        页面控制器
/// measure               文本缩放比例
/// startTime             Clash Core启动时间
/// navigatorKey          MaterialApp的navigatorKey
/// homeScaffoldKey       主页的Scaffold的key
///
class GlobalState {
  Timer? timer;
  Timer? groupsUpdateTimer;
  var isVpnService = false;
  late PackageInfo packageInfo;
  Function? updateCurrentDelayDebounce;
  PageController? pageController;
  late Measure measure;
  DateTime? startTime;
  final navigatorKey = GlobalKey<NavigatorState>();
  late AppController appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  List<Function> updateFunctionLists = [];

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  startListenUpdate() {
    if (timer != null && timer!.isActive == true) return;
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      for (final function in updateFunctionLists) {
        function();
      }
    });
  }

  stopListenUpdate() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
  }

  // 更新Clash配置到Clash Core
  Future<void> updateClashConfig({
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await config.currentProfile?.checkAndUpdate();
    final res = await clashCore.updateConfig(
      UpdateConfigParams(
        profileId: config.currentProfileId ?? "",
        config: clashConfig,
        params: ConfigExtendedParams(
          isPatch: isPatch,
          isCompatible: true,
          selectedMap: config.currentSelectedMap,
          overrideDns: config.overrideDns,
          testUrl: config.appSetting.testUrl,
        ),
      ),
    );
    if (res.isNotEmpty) throw res;
  }

  // 读取Clash Core的版本信息
  updateCoreVersionInfo(AppState appState) {
    appState.versionInfo = clashCore.getVersionInfo();
  }

  // 启动Clash Core
  handleStart({
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    clashCore.start();
    if (globalState.isVpnService) {
      await vpn?.startVpn();
      startListenUpdate();
      return;
    }
    startTime ??= DateTime.now();
    await preferences.saveClashConfig(clashConfig);
    await preferences.saveConfig(config);
    await service?.init();
    startListenUpdate();
  }

  // 读取Clash Core的运行时间
  updateStartTime() {
    startTime = clashCore.getRunTime();
  }

  // 停止Clash Core
  Future handleStop() async {
    clashCore.stop();
    if (Platform.isAndroid) {
      clashCore.stopTun();
    }
    await service?.destroy();
    startTime = null;
    stopListenUpdate();
  }

  Future applyProfile({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    await updateClashConfig(
      clashConfig: clashConfig,
      config: config,
      isPatch: false,
    );
    await updateGroups(appState);
    await updateProviders(appState);
  }

  // 读取Clash Core的ExternalProviders
  updateProviders(AppState appState) async {
    appState.providers = await clashCore.getExternalProviders();
  }

  // 初始化Clash Core
  init({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    appState.isInit = clashCore.isInit;
    if (!appState.isInit) {
      appState.isInit = await clashService.init(
        config: config,
        clashConfig: clashConfig,
      );
    }
    clashCore.setState(
      CoreState(
        enable: config.vpnProps.enable,
        accessControl: config.isAccessControl ? config.accessControl : null,
        ipv6: config.vpnProps.ipv6,
        allowBypass: config.vpnProps.allowBypass,
        systemProxy: config.vpnProps.systemProxy,
        onlyProxy: config.appSetting.onlyProxy,
        bypassDomain: config.vpnProps.bypassDomain,
        currentProfileName:
            config.currentProfile?.label ?? config.currentProfileId ?? "",
      ),
    );
    updateCoreVersionInfo(appState);
  }

  // 读取Clash Core的ProxyGroups
  Future<void> updateGroups(AppState appState) async {
    appState.groups = await clashCore.getProxiesGroups();
  }

  // 显示消息提示
  showMessage({
    required String title,
    required InlineSpan message,
    Function()? onTab,
    String? confirmText,
  }) {
    showCommonDialog(
      child: Builder(
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: Container(
              width: 300,
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message],
                  ),
                  style: const TextStyle(
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: onTab ??
                    () {
                      Navigator.of(context).pop();
                    },
                child: Text(confirmText ?? appLocalizations.confirm),
              )
            ],
          );
        },
      ),
    );
  }

  // 切换Clash Core的Proxy
  changeProxy({
    required Config config,
    required String groupName,
    required String proxyName,
  }) {
    clashCore.changeProxy(
      ChangeProxyParams(
        groupName: groupName,
        proxyName: proxyName,
      ),
    );
    if (config.appSetting.closeConnections) {
      clashCore.closeConnections();
    }
  }

  // 显示通用对话框
  Future<T?> showCommonDialog<T>({
    required Widget child,
    bool dismissible = true,
  }) async {
    return await showModal<T>(
      context: navigatorKey.currentState!.context,
      configuration: FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
        barrierDismissible: dismissible,
      ),
      builder: (_) => child,
      filter: filter,
    );
  }

  // 读取Clash Core的流量信息
  updateTraffic({
    AppFlowingState? appFlowingState,
  }) {
    final traffic = clashCore.getTraffic();
    if (Platform.isAndroid && isVpnService == true) {
      vpn?.startForeground(
        title: clashCore.getCurrentProfileName(),
        content: "$traffic",
      );
    } else {
      if (appFlowingState != null) {
        appFlowingState.addTraffic(traffic);
        appFlowingState.totalTraffic = clashCore.getTotalTraffic();
      }
    }
  }

  // 显示底部消息通知
  showSnackBar(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
  }) {
    final width = context.viewWidth;
    EdgeInsets margin;
    if (width < 600) {
      margin = const EdgeInsets.only(
        bottom: 16,
        right: 16,
        left: 16,
      );
    } else {
      margin = EdgeInsets.only(
        bottom: 16,
        left: 16,
        right: width - 316,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        action: action,
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: margin,
      ),
    );
  }

  // 执行异步方法并捕获异常，显示错误提示
  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
  }) async {
    try {
      final res = await futureFunction();
      return res;
    } catch (e) {
      showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      return null;
    }
  }

  // 打开外部链接
  openUrl(String url) {
    showMessage(
      message: TextSpan(text: url),
      title: appLocalizations.externalLink,
      confirmText: appLocalizations.go,
      onTab: () {
        launchUrl(Uri.parse(url));
      },
    );
  }
}

final globalState = GlobalState();
