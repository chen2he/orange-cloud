//
//  RuleValidateSection.swift
//  Orange Cloud
//
//  规则编辑器里的「校验」：Rulesets 写端点支持 ?dry_run=true，只校验不落库（成功 result 为 null）。
//  WAF 自定义规则与缓存规则编辑器共用。保存流程不变——校验是可选的预检，失败信息走编辑器原有的
//  错误区（viewModel.error），通过时在这里显示「规则校验通过」。
//

import SwiftUI

struct RuleValidateSection: View {

    let isValidating: Bool
    let passed: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                HStack(spacing: 8) {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                    Text("校验")
                    Spacer()
                    if passed && !isValidating {
                        Label("规则校验通过", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(disabled)
        }
    }
}
