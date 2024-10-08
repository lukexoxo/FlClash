import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// 安卓版窗口容器
class AndroidContainer extends StatefulWidget {
  final Widget child;

  const AndroidContainer({
    super.key,
    required this.child,
  });

  @override
  State<AndroidContainer> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends State<AndroidContainer>
    with WidgetsBindingObserver {
  Widget _excludeContainer(Widget child) {
    return Selector<Config, bool>(
      selector: (_, config) => config.isExclude,
      builder: (_, isExclude, child) {
        app?.updateExcludeFromRecents(isExclude);
        return child!;
      },
      child: child,
    );
  }

  // 设置状态栏和导航栏样式
  Widget _systemUiOverlayContainer(Widget child) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    // edgeToEdge 沉浸式模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
  }

  // 监听应用生命周期
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    final isPaused = state == AppLifecycleState.paused;
    if (isPaused) {
      await globalState.appController.savePreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _systemUiOverlayContainer(
      _excludeContainer(widget.child),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
