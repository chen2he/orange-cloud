// HarmonyOS Design 半模态（Half-Modal）统一样式：底部半模态 + 拖拽条 + 中/大两档高度 + 关闭按钮。
// 添加/编辑类操作统一走此选项，替换各处零散的 bindSheet 配置，保证一致的半模态观感。
// 用法：.bindSheet(this.xVisible, this.xSheet(), ocSheet(() => { this.xVisible = false; }))

export function ocSheet(onDisappear: () => void): SheetOptions {
  const opts: SheetOptions = {
    // 大/中两档：默认大档（数组首项为初始高度），可向下拖到中档
    detents: [SheetSize.LARGE, SheetSize.MEDIUM],
    preferType: SheetType.BOTTOM,
    dragBar: true,
    showClose: true,
    backgroundColor: $r('sys.color.background_secondary'),
    onDisappear: onDisappear,
  };
  return opts;
}

/// 简单/短表单：单档中等高度（如只有一两个输入的确认类），仍带拖拽条。
export function ocSheetCompact(onDisappear: () => void): SheetOptions {
  const opts: SheetOptions = {
    detents: [SheetSize.MEDIUM],
    preferType: SheetType.BOTTOM,
    dragBar: true,
    showClose: true,
    backgroundColor: $r('sys.color.background_secondary'),
    onDisappear: onDisappear,
  };
  return opts;
}
