import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'application.dart';
import 'l10n/l10n.dart';
import 'models/models.dart';
import 'common/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  clashCore.initMessage();
  globalState.packageInfo = await PackageInfo.fromPlatform();
  final version = await system.version;
  final config = await preferences.getConfig() ?? Config();
  final clashConfig = await preferences.getClashConfig() ?? ClashConfig();
  await android?.init();
  await window?.init(config.windowProps, version);
  final appState = AppState(
    mode: clashConfig.mode,
    version: version,
    selectedMap: config.currentSelectedMap,
  );
  appState.navigationItems = navigation.getItems(
    openLogs: config.appSetting.openLogs,
    hasProxies: false,
  );
  await globalState.init(
    appState: appState,
    config: config,
    clashConfig: clashConfig,
  );
  HttpOverrides.global = FlClashHttpOverrides();
  runAppWithPreferences(
    const Application(),
    appState: appState,
    config: config,
    clashConfig: clashConfig,
  );
}

// 原生调用Dart的入口
// 利用 DartExecutor 动态绑定 Dart 函数，灵活实现跨平台调用
// VpnPlugin.start 时调用此函数
// 确保不会被树摇优化（编译优化，移除未使用的代码）去除
@pragma('vm:entry-point')
Future<void> vpnService() async {
  debugPrint("vpnService");
  WidgetsFlutterBinding.ensureInitialized();
  globalState.isVpnService = true;
  globalState.packageInfo = await PackageInfo.fromPlatform();
  final version = await system.version;
  final config = await preferences.getConfig() ?? Config();
  final clashConfig = await preferences.getClashConfig() ?? ClashConfig();
  final appState = AppState(
    mode: clashConfig.mode,
    selectedMap: config.currentSelectedMap,
    version: version,
  );
  await globalState.init(
    appState: appState,
    config: config,
    clashConfig: clashConfig,
  );

  vpn?.setServiceMessageHandler(
    ServiceMessageHandler(
      onProtect: (Fd fd) async {
        await vpn?.setProtect(fd.value);
        clashCore.setFdMap(fd.id);
      },
      onProcess: (Process process) async {
        final packageName = await vpn?.resolverProcess(process);
        clashCore.setProcessMap(
          ProcessMapItem(
            id: process.id,
            value: packageName ?? "",
          ),
        );
      },
      onStarted: (String runTime) async {
        await globalState.applyProfile(
          appState: appState,
          config: config,
          clashConfig: clashConfig,
        );
      },
      onLoaded: (String groupName) {
        final currentSelectedMap = config.currentSelectedMap;
        final proxyName = currentSelectedMap[groupName];
        if (proxyName == null) return;
        globalState.changeProxy(
          config: config,
          groupName: groupName,
          proxyName: proxyName,
        );
      },
    ),
  );
  final appLocalizations = await AppLocalizations.load(
    other.getLocaleForString(config.appSetting.locale) ??
        WidgetsBinding.instance.platformDispatcher.locale,
  );
  await app?.tip(appLocalizations.startVpn);
  await globalState.handleStart(
    config: config,
    clashConfig: clashConfig,
  );

  tile?.addListener(
    TileListenerWithVpn(
      onStop: () async {
        await app?.tip(appLocalizations.stopVpn);
        await globalState.handleStop();
        clashCore.shutdown();
        exit(0);
      },
    ),
  );

  globalState.updateTraffic();
  globalState.updateFunctionLists = [
    () {
      globalState.updateTraffic();
    }
  ];
}

@immutable
class ServiceMessageHandler with ServiceMessageListener {
  final Function(Fd fd) _onProtect;
  final Function(Process process) _onProcess;
  final Function(String runTime) _onStarted;
  final Function(String providerName) _onLoaded;

  const ServiceMessageHandler({
    required Function(Fd fd) onProtect,
    required Function(Process process) onProcess,
    required Function(String runTime) onStarted,
    required Function(String providerName) onLoaded,
  })  : _onProtect = onProtect,
        _onProcess = onProcess,
        _onStarted = onStarted,
        _onLoaded = onLoaded;

  @override
  onProtect(Fd fd) {
    _onProtect(fd);
  }

  @override
  onProcess(Process process) {
    _onProcess(process);
  }

  @override
  onStarted(String runTime) {
    _onStarted(runTime);
  }

  @override
  onLoaded(String providerName) {
    _onLoaded(providerName);
  }
}

@immutable
class TileListenerWithVpn with TileListener {
  final Function() _onStop;

  const TileListenerWithVpn({
    required Function() onStop,
  }) : _onStop = onStop;

  @override
  void onStop() {
    _onStop();
  }
}
