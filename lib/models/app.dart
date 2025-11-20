import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/selector.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'common.dart';
import 'core.dart';

part 'generated/app.freezed.dart';

typedef DelayMap = Map<String, Map<String, int?>>;

/// AppState: 应用运行状态，使用riverpod同步管理
/// 
/// isInit: Clash Core是否初始化
/// backBlock: 是否禁用返回按钮，禁用返回点返回无作用
/// pageLabel: 当前显示的页面标签
/// packages: 安装包列表
/// sortNum: 排序编号，用于代理测速后触发列表UI刷新
/// viewSize: 窗口视图大小，宽高
/// sideWidth: 侧边栏宽度
/// delayMap: 代理测速延迟存储
/// groups: 代理组列表
/// checkIpNum: 用于触发本地IP检测，更新本地IP信息
/// brightness: 系统主题模式
/// runTime: 根据startTime计算的运行时间
/// providers: Clash提供者
/// localIp: 本地IP
/// requests: 请求连接列表，Clash Core内核回调onRequest请求连接信息
/// version: 系统版本号，windows版本号，android sdk版本号，macos版本号
/// logs: 日志列表，Clash Core内核回调onLog日志
/// traffics: 流量列表，Clash Core getTraffic()获取的流量信息
/// totalTraffic: 总流量，Clash Core getTotalTraffic()获取的总流量信息
/// realTunEnable: Tun模式是否正在运行，macos/windows/linux
/// loading: 有异步任务进行中，用于显示加载中UI
/// systemUiOverlayStyle: 系统UI覆盖样式
/// profileOverrideModel: Clash配置覆盖
/// queryMap: 存储不同页面的查询关键词
/// coreStatus: Clash Core状态，连接中，连接成功，连接失败
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    @Default(false) bool isInit,
    @Default(false) bool backBlock,
    @Default(PageLabel.dashboard) PageLabel pageLabel,
    @Default([]) List<Package> packages,
    @Default(0) int sortNum,
    required Size viewSize,
    @Default(0) double sideWidth,
    @Default({}) DelayMap delayMap,
    @Default([]) List<Group> groups,
    @Default(0) int checkIpNum,
    required Brightness brightness,
    int? runTime,
    @Default([]) List<ExternalProvider> providers,
    String? localIp,
    required FixedList<TrackerInfo> requests,
    required int version,
    required FixedList<Log> logs,
    required FixedList<Traffic> traffics,
    required Traffic totalTraffic,
    @Default(false) bool realTunEnable,
    @Default(false) bool loading,
    required SystemUiOverlayStyle systemUiOverlayStyle,
    ProfileOverrideModel? profileOverrideModel,
    @Default({}) Map<QueryTag, String> queryMap,
    @Default(CoreStatus.connecting) CoreStatus coreStatus,
  }) = _AppState;
}

extension AppStateExt on AppState {
  ViewMode get viewMode => utils.getViewMode(viewSize.width);

  bool get isStart => runTime != null;
}
