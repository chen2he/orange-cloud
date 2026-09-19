//
//  AvailabilityCompat.swift
//  Orange Cloud
//
//  集中存放跨 iOS 版本的 SwiftUI 兼容封装：基线 iOS 17，对 iOS 18+ 专属 API
//  统一在此降级，避免在各视图里散落 #available 守卫。
//

import SwiftUI
import UIKit
import TipKit

extension ProcessInfo {
    /// 当前系统是否落在 iOS 17.0.x（17.0 / 17.0.1 / 17.0.2 / 17.0.3）。
    /// 这一窄段的 TipKit 把 popover 锚定到导航栏 bar button 时，会在
    /// `-[UINavigationBar layoutSubviews]` 阶段抛未捕获异常导致崩溃，Apple 自 17.1 起修复。
    /// 仅用于对这段版本做最小化 UI 降级，勿扩大到 17.1+。
    nonisolated static var isBuggyTipKitNavBar: Bool {
        let v = processInfo.operatingSystemVersion
        return v.majorVersion == 17 && v.minorVersion == 0
    }
}

extension View {
    /// `popoverTip` 的安全封装：iOS 17.0.x 上跳过（见 ``ProcessInfo/isBuggyTipKitNavBar``），
    /// 避免导航栏锚定的 TipKit popover 崩溃；17.1+ 与更高版本行为不变，正常展示气泡提示。
    /// 适用于挂在工具栏 bar button 上的提示；非导航栏场景同样安全（17.0.x 仅少展示一次提示）。
    ///
    /// `enabled` 供调用方按画布再关一道：宽画布（regular）顶部有 Tab 胶囊，锚在工具栏按钮上的
    /// popover 会横着盖住它，那种场合改用页内 `TipView`，见 DashboardView 的 accountSwitchTip。
    @ViewBuilder
    func safePopoverTip<T: Tip>(_ tip: T, enabled: Bool = true) -> some View {
        if !enabled || ProcessInfo.isBuggyTipKitNavBar {
            self
        } else {
            popoverTip(tip)
        }
    }
}

// MARK: - 统一动效信号

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// App 设置里「减少动画」开关的值（独立于系统辅助功能「减弱动态效果」）。在根视图注入，
    /// 让系统级转场（Zoom 导航转场）与自定义动画（玻璃岛浮现 / 骨架闪烁）都能跟着这个开关走——
    /// 否则开关只接了全局 .transaction，盖不住导航转场与只读系统设置的浮现动画，用户感觉「开了没用」。
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// 详情页：iOS 18+ 应用 Zoom 导航转场；iOS 17 或开启「减少动画」时原样返回（标准 push）。
    func zoomNavigationTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomNavigationTransition(sourceID: sourceID, namespace: namespace))
    }

    /// 源视图（列表行）：iOS 18+ 标记 Zoom 转场源；iOS 17 无操作。
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// 刷新中持续动画：iOS 18+ 用 .rotate 旋转；iOS 17 回退 .pulse
    /// （.rotate 的“持续效果”conformance 自 iOS 18 起才有）。
    @ViewBuilder
    func loadingSpinSymbolEffect(isActive: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.rotate, isActive: isActive)
        } else {
            symbolEffect(.pulse, isActive: isActive)
        }
    }

    /// 出现时弹一下（一次性 bounce）：iOS 18+ 用 .nonRepeating 持续效果；
    /// iOS 17 静态显示（.bounce 的“持续效果”conformance 自 iOS 18 起才有）。
    @ViewBuilder
    func oneShotBounceSymbolEffect() -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.bounce, options: .nonRepeating)
        } else {
            self
        }
    }
}

/// Zoom 导航转场（iOS 18+），开启「减少动画」时降级为标准 push。
/// 读环境注入的 appReduceMotion——系统「减弱动态效果」由系统自动让 .zoom 回退，这里只额外接 App 开关。
private struct ZoomNavigationTransition<ID: Hashable>: ViewModifier {
    @Environment(\.appReduceMotion) private var appReduceMotion
    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !appReduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

extension Color {
    /// Color.mix(with:by:) 的兼容封装：iOS 18+ 用系统实现；iOS 17 回退 UIColor 的 RGB 线性插值。
    nonisolated func mixed(with other: Color, by amount: Double) -> Color {
        if #available(iOS 18.0, *) {
            return mix(with: other, by: amount)
        }
        let t = max(0, min(1, amount))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(self).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(other).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            .sRGB,
            red:   Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue:  Double(ab + (bb - ab) * t),
            opacity: Double(aa + (ba - aa) * t)
        )
    }
}

// MARK: - iPhone Duo：竖轴工具栏与 Tab 栏
// iPhone Duo 的外屏（以及内屏横屏）把状态栏 / 工具栏 / Tab 栏一起放到侧边竖轴，
// 给内容留出竖向空间。用标准组件就自动拿到这套布局，我们要做的是三件事：
// ① 给长列表页开「滚动时收起 Tab 栏」；② 让溢出顺序按动作重要性走，而不是默认的从下往上；
// ③ 自建的「更多」菜单并进系统溢出菜单（HIG：ellipsis 只留给系统菜单）。
// 参考 HIG「Designing for iPhone Duo」（2026-09-09）。

extension View {
    /// 向下滚动时最小化 Tab 栏（iOS 26+），把竖向空间让给内容；iOS 18 / 17 无操作。
    /// Duo 外屏又宽又矮，Tab 栏还和工具栏挤在同一条竖轴上，滚动时收起收益最大。
    /// **只在 compact 宽度开**：regular（iPad / Duo 内屏）的 Tab 胶囊在顶部、不占竖向内容区，
    /// 收起反而让人找不着，故显式给 `.never`——用同一个修饰器只换参数，不按画布切换修饰器结构，
    /// 免得 size class 翻转时 TabView 换 identity 被整个重建（见 MainTabView 里的 .id 禁令）。
    func ocTabBarMinimizeOnScroll() -> some View {
        modifier(TabBarMinimizeOnScroll())
    }

    /// 把一组动作并入**系统**溢出菜单（iOS 27+）；以下版本无操作，调用方需自备 ellipsis 菜单
    /// （用 ``ProcessInfo/usesSystemToolbarOverflow`` 判断该不该挂自建菜单，两边共用同一份菜单内容）。
    @ViewBuilder
    func ocOverflowActions<C: View>(@ViewBuilder content: @escaping () -> C) -> some View {
        #if compiler(>=6.4)     // 见文件末尾「为什么按编译器版本分档」
        if #available(iOS 27.0, *) {
            toolbarOverflowMenu(content: content)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension ProcessInfo {
    /// 当前系统是否自带工具栏溢出菜单（iOS 27+）。为 true 时别再挂自建的 ellipsis 菜单，
    /// 动作交给 ``SwiftUI/View/ocOverflowActions(content:)`` 并入系统菜单。
    nonisolated static var usesSystemToolbarOverflow: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { true } else { false }
        #else
        false   // 用 iOS 26 SDK 编的包里没有系统溢出菜单，调用方继续挂自建 ellipsis
        #endif
    }
}

/// 工具栏项在竖轴上的保留优先级。空间不够时系统默认**从下往上**把项目收进溢出菜单，
/// 于是「新建 / 添加」这类主动作反而先被收走；标成 high 让它留到最后，
/// 刷新 / 排序这类随时能从菜单里找到的标成 low。iOS 27 以下无操作。
enum OCToolbarPriority {
    /// 页面主动作（新建、添加、编辑），最后才溢出
    case primary
    /// 辅助动作（刷新、排序），优先溢出
    case secondary

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    var resolved: ToolbarItemVisibilityPriority {
        switch self {
        case .primary:   .high
        case .secondary: .low
        }
    }
    #endif
}

extension ToolbarContent {
    /// ``OCToolbarPriority`` 的兼容封装：iOS 27+ 落到 `visibilityPriority`，以下版本原样返回。
    @ToolbarContentBuilder
    func ocPriority(_ priority: OCToolbarPriority) -> some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            visibilityPriority(priority.resolved)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// ocTabBarMinimizeOnScroll 的实现载体（要读 horizontalSizeClass 环境）
private struct TabBarMinimizeOnScroll: ViewModifier {

    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(sizeClass == .compact ? .onScrollDown : .never)
        } else {
            content
        }
    }
}

// MARK: - 为什么按编译器版本分档
// `visibilityPriority` / `ToolbarItemVisibilityPriority` / `toolbarOverflowMenu` 是 **iOS 27 SDK**
// 才有的符号——`if #available` 只挡运行期，**挡不住编译期**：用 iOS 26 SDK 编译时这些名字根本不存在，
// 直接报 "cannot find in scope"（Xcode Cloud 的 "Latest Release" 当时是 Xcode 26.6 / iPhoneOS 26.5 SDK，
// build 51 就是这么挂的）。故再套一层 `#if compiler(>=6.4)`：Swift 6.4 随 Xcode 27 一起发布，
// 等价于「手上这套工具链带 iOS 27 SDK」。
//
// 代价要知道：**用 Xcode 26.x 编出来的包里，这三件事会被编译掉**——工具栏溢出优先级、
// 系统溢出菜单都不存在，自建 ellipsis 菜单会继续显示（`usesSystemToolbarOverflow` 返回 false 兜住了）。
// 另外 iPhone Duo / 可调尺寸的自动 opt-in 同样只在用 iOS 27 SDK 归档时才生效。
// 要完整效果，Xcode Cloud 的工作流得把 Xcode 版本选到 27（"Xcode 27 Release Candidate"）。
