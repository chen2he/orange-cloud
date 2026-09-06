// 页面底：HarmonyOS 系统分层参数（sys.color.background_secondary），深浅色由系统接管。
// 「晨昏」不再整屏铺天色——只在概览页顶部与服务卡片保留签名点缀（见 DaybreakHeader / widget）。
@Component
export struct OCSky {
  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
  }
}

/// 全屏底色（各 NavDestination 根）
@Component
export struct OCSkyBackground {
  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
  }
}
