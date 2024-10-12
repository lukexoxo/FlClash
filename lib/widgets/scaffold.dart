import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommonScaffold extends StatefulWidget {
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? sideNavigationBar;
  final String title;
  final Widget? leading; // 顶部栏左侧的组件
  final List<Widget>? actions; // 顶部栏右侧的操作按钮列表
  final bool automaticallyImplyLeading; // 是否自动添加返回按钮

  const CommonScaffold({
    super.key,
    required this.body,
    this.sideNavigationBar,
    this.bottomNavigationBar,
    this.leading,
    required this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  CommonScaffold.open({
    Key? key,
    required Widget body,
    required String title,
    required Function onBack,
  }) : this(
          key: key,
          body: body,
          title: title,
          automaticallyImplyLeading: false,
          leading: SizedBox(
            height: kToolbarHeight,
            child: IconButton(
              icon: const BackButtonIcon(),
              onPressed: () {
                onBack();
              },
            ),
          ),
        );

  @override
  State<CommonScaffold> createState() => CommonScaffoldState();
}

class CommonScaffoldState extends State<CommonScaffold> {
  final ValueNotifier<List<Widget>> _actions = ValueNotifier([]);
  final ValueNotifier<bool> _loading = ValueNotifier(false);

  set actions(List<Widget> actions) {
    if (_actions.value != actions) {
      _actions.value = actions;
    }
  }

  // 在执行异步任务时，显示 LinearProgressIndicator。
  // 如果异步任务抛出异常，捕获并通过 globalState.showMessage 显示错误信息。
  Future<T?> loadingRun<T>(
    Future<T> Function() futureFunction, {
    String? title,
  }) async {
    _loading.value = true;
    try {
      final res = await futureFunction();
      _loading.value = false;
      return res;
    } catch (e) {
      globalState.showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      _loading.value = false;
      return null;
    }
  }

  @override
  void dispose() {
    _actions.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CommonScaffold oldWidget) {
    // 如果组件的 title 发生了变化，则重置 actions
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _actions.value = [];
    }
  }

  Widget? get _sideNavigationBar => widget.sideNavigationBar;

  Widget get body => SafeArea(child: widget.body);

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      // 当键盘弹出时，页面的 body 会自动调整大小
      resizeToAvoidBottomInset: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // 监听 actions 的变化，当 actions 发生变化时更新右侧操作按钮。
            ValueListenableBuilder<List<Widget>>(
              valueListenable: _actions,
              builder: (_, actions, __) {
                final realActions =
                    actions.isNotEmpty ? actions : widget.actions;
                return AppBar(
                  centerTitle: false,
                  systemOverlayStyle: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness:
                        Theme.of(context).brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                    systemNavigationBarIconBrightness:
                        Theme.of(context).brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                    systemNavigationBarColor: widget.bottomNavigationBar != null
                        ? context.colorScheme.surfaceContainer
                        : context.colorScheme.surface,
                    systemNavigationBarDividerColor: Colors.transparent,
                  ),
                  automaticallyImplyLeading: widget.automaticallyImplyLeading,
                  leading: widget.leading,
                  title: Text(widget.title),
                  actions: [
                    ...?realActions,
                    const SizedBox(
                      width: 8,
                    )
                  ],
                );
              },
            ),
            // 监听 _loading 的状态，显示或隐藏 LinearProgressIndicator
            ValueListenableBuilder(
              valueListenable: _loading,
              builder: (_, value, __) {
                return value == true
                    ? const LinearProgressIndicator()
                    : Container();
              },
            ),
          ],
        ),
      ),
      body: body,
      bottomNavigationBar: widget.bottomNavigationBar,
    );
    return _sideNavigationBar != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sideNavigationBar!,
              Expanded(
                flex: 1,
                child: Material(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: scaffold,
                  ),
                ),
              ),
            ],
          )
        : scaffold;
  }
}
