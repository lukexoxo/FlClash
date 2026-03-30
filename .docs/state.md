## FlClash 状态管理架构（Riverpod）

### 1. 核心思路

本项目采用 **“单例全局状态 `globalState` + Riverpod 作为响应式访问层 + Manager/Controller 负责副作用编排”** 的组合架构：

1. `lib/state.dart` 中的 `globalState` 作为“真实状态存储”（承载 `config` 与 `appState`，并承担部分跨层逻辑，如初始化、持久化、启动/停止 core）。
2. `lib/providers/*` 把 `globalState` 暴露成 Riverpod provider，供 UI 与其他层读取。
3. `lib/controller.dart` 的 `AppController` 作为“业务编排入口”，用 `WidgetRef` 驱动 provider 变化并调用 `coreController` 等外部能力。
4. `lib/manager/*` 使用 `ref.listenManual(...)` 监听 provider 的变化，在变化发生时触发副作用（更新 ClashCore 配置、保存偏好、托盘/窗口/热键/system DNS 等平台集成）。
5. `core` 层产生的事件（如 onLog/onRequest/onDelay/onLoaded）由 `CoreManager` 回写到对应 provider，从而驱动 UI 刷新。

### 2. 状态分区：config / appState / 派生状态

#### 2.1 `globalState.config`：可持久化的配置状态

`lib/state.dart` 中 `GlobalState` 包含 `late Config config;`，其内容主要来自用户配置（主题、代理、订阅、窗口等）。

对应的 provider 在 `lib/providers/config.dart` 中定义，典型模式如下：

- Provider 的 `build()` 返回 `globalState.config.xxx`
- `onUpdate(value)` / `updateState(...)` 把新值写回 `globalState.config = globalState.config.copyWith(...)`

例如 `AppSetting` provider 会把更新同步到 `globalState.config.appSetting`。

#### 2.2 `globalState.appState`：运行态状态（不强调持久化）

`lib/providers/app.dart` 定义“应用运行态”的 provider，例如：

- 日志列表（`Logs`）
- 请求追踪（`Requests`）
- 运行时间/流量（`RunTime`/`Traffics`/`TotalTraffic`）
- 当前页面/导航、窗口视图尺寸（`ViewSize`/`SideWidth` 等）
- core 连接状态（`CoreStatus`）

这些 provider 同样遵循：

- `build()` 读取 `globalState.appState.xxx`
- `onUpdate(value)` 写回 `globalState.appState = globalState.appState.copyWith(...)`

#### 2.3 `lib/providers/state.dart`：聚合/派生/计算类 provider

`lib/providers/state.dart` 用大量 `@riverpod` 函数 provider 来聚合其它 provider，输出 UI 更直接可用的数据结构，例如：

- 导航项：`navigationItemsStateProvider`、`currentNavigationItemsStateProvider`
- “是否启动/是否显示”：`isStartProvider`、`StartButtonSelectorState`
- 计算视图布局：`contentWidthProvider`、`getProxiesColumnsProvider`
- 计算当前分组/代理选择：`realSelectedProxyStateProvider` 等

这层 provider 的特点是：

- 通常只 `ref.watch(...)` 不直接写回 `globalState`
- 使用 `.select(...)` 精确订阅字段，避免不必要重建

### 3. Riverpod Provider 的类别与生成方式

#### 3.1 Provider 类型

本项目主要使用三类 provider：

1. `Notifier` 类 provider（可修改状态）
   - 在 `lib/providers/app.dart` 与 `lib/providers/config.dart` 中
   - 通过 `AutoDisposeNotifierMixin` 把变更同步回 `globalState`
2. “函数型 provider”（派生/聚合/只读）
   - 在 `lib/providers/state.dart` 中
   - 通过 `@riverpod` 生成对应的 provider
3. 参数化 provider（family）
   - 例如 `filterGroupsStateProvider(query)`、`getDelayProvider(proxyName/ testUrl)` 这类

#### 3.2 代码生成

provider 使用 `riverpod_annotation` + `part 'generated/*.g.dart'` 生成代码。

### 4. Provider 更新如何落回 `globalState`：AutoDisposeNotifierMixin

`lib/common/mixin.dart` 定义了 `AutoDisposeNotifierMixin`/`AnyNotifierMixin`，在 provider 状态写入时触发同步：

- 当 `ref.mounted` 时：直接 `state = value`
- 当不 mounted 时：调用 `onUpdate(value)` 兜底写回 `globalState`
- 在 `updateShouldNotify` 为真时，也会调用 `onUpdate(next)` 确保同步

这使得“UI/业务修改 provider”能够始终最终反映到 `globalState` 中，形成一致的状态落点。

### 5. 副作用编排：Manager 使用 `ref.listenManual`

为了避免把 side effect 写进 UI，本项目在 `lib/manager/*` 中集中监听 provider 变化并执行动作。

核心示例是：

#### 5.1 `CoreManager`：监听配置/开关并接收 core 事件回写

- 监听 `needSetupProvider`：profile 或 setup 需求变化时调用 `globalState.appController.handleChangeProfile()`
- 监听 `updateParamsProvider`：变化时触发 `globalState.appController.updateClashConfigDebounce()`
- 监听 `appSettingProvider.openLogs`：打开/关闭 core 日志输出
- 实现 `CoreEventListener`：
  - `onLog`：写入 `logsProvider`
  - `onRequest`：写入 `requestsProvider`
  - `onDelay`：写入 delay 数据源并触发分组刷新（debounce）

`ref.listenManual` 的组合让“配置变更 -> 更新 core -> 事件回写 provider -> UI 刷新”的链路清晰可控。

#### 5.2 `AppStateManager`：生命周期/系统事件与 provider 联动

`lib/manager/app_manager.dart`：

- `checkIpProvider` 变化触发出口 IP 检测（由 `detectionState` 负责去抖与请求）
- `configStateProvider` 变化触发 `savePreferencesDebounce()`
- `needUpdateGroupsProvider` 变化触发 `updateGroupsDebounce()`
- 处理 `WidgetsBindingObserver`：应用 resumed 时恢复渲染、Android 上尝试启动 core

### 6. 典型数据流（从 UI 到 Core 再到 UI）

以“切换模式/切换 profile/更新配置”为例，可概括为：

1. UI 调用 `globalState.appController.xxx(...)` 或直接操作某个 provider 的 notifier
2. provider 的 `onUpdate` 把新状态写回 `globalState.config` 或 `globalState.appState`
3. `CoreManager`/`AppStateManager` 通过 `ref.listenManual` 监听到变化
4. `CoreManager` 触发 `AppController`：
   - setup/update ClashCore 配置
   - 重载外部 provider（分组/节点列表刷新）
5. core 回调事件（log/request/delay/...）由 `CoreManager` 回写到对应 provider
6. UI 使用 `ref.watch(...)` 订阅相关 provider，自动刷新

### 7. 生命周期：Application 初始化与 ProviderScope

入口在 `lib/main.dart`：

- `globalState.initApp(version)` 初始化 `globalState.config/appState`、动态主题、偏好加载等
- `runApp(ProviderScope(child: const Application()))`

`lib/application.dart` 在 `initState` 中：

- 设置 `globalState.appController = AppController(context, ref)`
- 调用 `globalState.appController.init()` 完成：
  - tray/window/vpn 等平台初始化
  - 连接/预加载 core
  - 初始化状态（根据配置 autoRun 等）

`Application` 的 `build()` 里通过 `Consumer` 从 provider 读取主题与语言等并构建 `MaterialApp`，其余 Manager 层在 Widget 树中串联：

- `AppStateManager` -> `CoreManager` -> `ConnectivityManager` -> 各平台 Manager（Tray/HotKey/Proxy/VPN 等）

### 8. 关键文件索引

- `lib/state.dart`
  - `GlobalState`：真正的状态存储、初始化与持久化落点
- `lib/providers/config.dart`
  - config 可持久化状态（写回 `globalState.config`）
- `lib/providers/app.dart`
  - app 运行态状态（写回 `globalState.appState`）
- `lib/providers/state.dart`
  - 派生/聚合计算 provider（主要读取，不直接写回）
- `lib/common/mixin.dart`
  - `AutoDisposeNotifierMixin`：provider 更新同步到 globalState 的关键机制
- `lib/controller.dart`
  - `AppController`：业务编排入口（读写 provider + 调用 core/平台能力）
- `lib/manager/core_manager.dart`
  - core 事件监听与 core 配置联动
- `lib/manager/app_manager.dart`
  - 生命周期与系统事件联动监听
- `lib/application.dart`
  - Widget 树组织（ProviderScope + 各 Manager 包裹）

---

如果你希望这份文档进一步“可操作化”（例如增加 `provider 调用/写回 globalState` 的检查清单，或给出 `needSetup/updateParams` 这两条链路的时序图），我也可以继续补充。
