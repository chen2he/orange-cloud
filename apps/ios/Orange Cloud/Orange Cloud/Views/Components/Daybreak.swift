//
//  Daybreak.swift
//  Orange Cloud
//
//  「晨昏」设计语言：亮色主题是白昼的天，暗色主题是夜空，同一场景的昼与夜。
//  天空做画布（SkyBackground），内容是浮在天色上的玻璃岛（glassIsland），
//  地平线弧（HorizonArc）上的太阳 / 月亮按真实时间走位。
//

import SwiftUI

// MARK: - 布局常量（全局统一，不再各处手写魔法数）

nonisolated enum OCLayout {
    /// 玻璃岛圆角
    static let islandRadius: CGFloat = 20
    /// 小岛 / 行内控件圆角
    static let chipRadius: CGFloat = 16
    /// 页面水平边距
    static let pagePadding: CGFloat = 16
    /// 岛与岛之间的间距
    static let islandGap: CGFloat = 12
    /// 岛内边距
    static let islandPadding: CGFloat = 14
    /// 宽画布下的内容可读宽度上限。对齐系统 readableContentGuide 的量级（~672pt）：
    /// 再宽下去一行的两端就拉开到几百点，「图标+标签贴最左、值/箭头贴最右」中间全是空白。
    /// iOS 27 起 App 会被自动 opt-in 可调尺寸（折叠机内屏 / iPhone 镜像 / iPad 上的 iPhone App），
    /// 单列拉通是宽幅下最普遍的一类失配。
    static let readableWidth: CGFloat = 672
}

// MARK: - 天空画布
// （天色相位 SkyPhase 已移至 Shared/SkyPhase.swift，与 Widget Extension 共用）

/// 全屏环境光背景。亮 / 暗主题分别取昼 / 夜的天色，随时段微调，跟随系统时钟每分钟更新。
struct SkyBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    /// 预览用固定时刻；nil 时跟随系统时钟
    var date: Date? = nil

    var body: some View {
        if let date {
            sky(at: date)
        } else {
            TimelineView(.everyMinute) { context in
                sky(at: context.date)
            }
        }
    }

    private func sky(at date: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: date)
        let phase = SkyPhase.current(colorScheme: colorScheme, hour: hour)
        return ZStack {
            LinearGradient(colors: phase.body, startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [phase.glow, .clear],
                center: UnitPoint(x: 0.5, y: -0.15),
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - 玻璃岛

/// 玻璃底色：视觉上等效 `.regularMaterial` 的半透明纯色（按主题实测校准，误差 ≤3/255）。
/// **不要改回真材质**：天空是平滑渐变，实时背景模糊对它的观感增益≈0，但每个岛/行
/// 都会各挂一个逐帧 backdrop blur 节点——列表滚动时几十个节点同时重采样，
/// 是 iPhone 12–14 级设备整页掉帧的主因（且与动画无关，「减少动画」开关救不了）。
/// 半透明纯色同样透出天色随高度的渐变变化，静态内容可被整层缓存，滚动零逐帧成本。
nonisolated enum OCGlass {
    static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.170, green: 0.163, blue: 0.157).opacity(0.85)
            : Color.white.opacity(0.55)
    }
}

/// 「晨昏」的内容容器：玻璃底透出天色 + 顶亮底暗的折射描边 + 软投影。
private struct GlassIsland: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(OCGlass.fill(for: colorScheme), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.16 : 0.55),
                                .white.opacity(colorScheme == .dark ? 0.03 : 0.10),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.07), radius: 12, y: 5)
    }
}

extension View {
    /// 把任意内容变成浮在天色上的玻璃岛
    func glassIsland(cornerRadius: CGFloat = OCLayout.islandRadius) -> some View {
        modifier(GlassIsland(cornerRadius: cornerRadius))
    }
}

// MARK: - 地平线弧

/// 问候区下方的细弧线，太阳（昼）/ 月亮（夜）按当前时刻在弧上走位，跟随系统时钟每分钟更新。
struct HorizonArc: View {

    @Environment(\.colorScheme) private var colorScheme
    /// 预览用固定时刻；nil 时跟随系统时钟
    var date: Date? = nil

    /// 当前时刻在所属半日里的进度：昼 6:00→18:00，夜 18:00→次日 6:00。
    /// 亮色画太阳、暗色画月亮，共用同一进度——白天开暗色时，
    /// 月亮取太阳此刻的弧位（同一时刻的夜面投影），任何主题/时刻组合下天体都不会钉死。
    private func progress(at date: Date) -> Double {
        let calendar = Calendar.current
        let minutes = Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        let day = (minutes - 6 * 60) / (12 * 60)
        if day >= 0 && day < 1 {
            return min(max(day, 0.02), 0.98)
        }
        let night = minutes >= 18 * 60 ? minutes - 18 * 60 : minutes + 6 * 60
        return min(max(night / (12 * 60), 0.02), 0.98)
    }

    var body: some View {
        if let date {
            arc(at: date)
        } else {
            TimelineView(.everyMinute) { context in
                arc(at: context.date)
            }
        }
    }

    private func arc(at date: Date) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let start = CGPoint(x: 0, y: height - 2)
            let end = CGPoint(x: width, y: height - 2)
            let control = CGPoint(x: width / 2, y: -height * 0.55)
            let t = CGFloat(progress(at: date))
            let mt: CGFloat = 1 - t
            let wStart: CGFloat = mt * mt
            let wControl: CGFloat = 2 * mt * t
            let wEnd: CGFloat = t * t
            let dotX: CGFloat = wStart * start.x + wControl * control.x + wEnd * end.x
            let dotY: CGFloat = wStart * start.y + wControl * control.y + wEnd * end.y
            let dot = CGPoint(x: dotX, y: dotY)

            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                }
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.16) : Color.ocOrange.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
                Circle()
                    .fill(colorScheme == .dark ? Color(red: 0.93, green: 0.93, blue: 0.98) : Color.ocOrange)
                    .frame(width: 7, height: 7)
                    .shadow(
                        color: (colorScheme == .dark ? Color.white : Color.ocOrange).opacity(0.6),
                        radius: 5
                    )
                    .position(dot)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 玻璃岛入场

/// 岛屿按序浮现（开启「减弱动态效果」时直接显示）
private struct IslandReveal: ViewModifier {

    @Environment(\.appReduceMotion) private var appReduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let index: Int
    @State private var shown = false

    /// App 开关 ∨ 系统「减弱动态效果」，任一开启即跳过浮现动画
    private var reduceMotion: Bool { appReduceMotion || systemReduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(.smooth(duration: 0.5).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// 玻璃岛错峰浮现，`index` 决定先后
    func islandReveal(_ index: Int) -> some View {
        modifier(IslandReveal(index: index))
    }

    /// 宽画布下把内容收进可读宽度并居中；compact 宽度原样返回、零影响。
    /// 只封顶不撑开——所以放进本来就窄的容器（如分栏的边栏）里也不会有副作用。
    func ocReadableWidth(_ maxWidth: CGFloat = OCLayout.readableWidth) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }

    /// List 页接入晨昏：隐藏系统底色，收进可读宽度，铺天空画布（配合 glassRow 使用）。
    /// 顺序要紧：先收窄 List，再铺天空——天空挂在收窄后的外层全宽 frame 上，
    /// 于是内容居中、天色仍然出血铺满。数据密集的表格页（D1 表、R2 对象列表）本就不走
    /// 这个修饰器，不受影响。
    func daybreakList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .ocReadableWidth()
            .background { SkyBackground() }
    }

    /// List 行 / Section 的玻璃底（系统按 insetGrouped 分组形状自动裁切圆角）。
    /// 用 OCGlass 纯色而非真材质：每行一个 backdrop blur 是列表掉帧主因，见 OCGlass 注释。
    func glassRow() -> some View {
        modifier(GlassRowBackground())
    }
}

/// ocReadableWidth 的实现载体（要读 horizontalSizeClass 环境）
private struct ReadableWidth: ViewModifier {

    @Environment(\.horizontalSizeClass) private var sizeClass

    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)   // 外层再撑满，把收窄后的内容顶到居中
        } else {
            content
        }
    }
}

/// glassRow 的实现载体（listRowBackground 的取色需要读 colorScheme 环境）
private struct GlassRowBackground: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.listRowBackground(Rectangle().fill(OCGlass.fill(for: colorScheme)))
    }
}

#Preview("昼 / 夜") {
    VStack(spacing: OCLayout.islandGap) {
        HorizonArc()
            .frame(height: 44)
        Text("玻璃岛")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OCLayout.islandPadding)
            .glassIsland()
    }
    .padding(OCLayout.pagePadding)
    .background { SkyBackground() }
}
