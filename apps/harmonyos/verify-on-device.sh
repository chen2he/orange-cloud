#!/usr/bin/env bash
# 鸿蒙版运行时验收脚本（在有 DevEco + 华为账号的机器上跑）。
# 当前环境实测：无连接设备 / 无模拟器实例 / 无已下载镜像 / 无签名材料，
# 故以下步骤的「①接受协议 ②下载镜像 ③华为账号签名」只能由机主本人完成——
# 它们不是缺硬件，是缺你的法律同意与账号凭据。脚本把其余全自动化。
set -e

DEVECO="/Applications/DevEco-Studio.app/Contents"
export DEVECO_SDK_HOME="$DEVECO/sdk"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
NODE="$DEVECO/tools/node/bin/node"
HVIGOR="$DEVECO/tools/hvigor/bin/hvigorw.js"
EMU="$DEVECO/tools/emulator/Emulator"
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
cd "$(dirname "$0")"

echo "==== 0. 设备/模拟器现状 ===="
"$HDC" list targets

echo "==== 1. 模拟器：接受协议 + 装镜像 + 建实例 + 启动（需华为账号）===="
echo "   如已有真机（开发者模式+USB），可跳过本段，直接连线让 hdc list targets 出设备。"
read -p "   要创建并启动 HarmonyOS 6.1.1(24) 模拟器吗？(y/N) " ans
if [ "$ans" = "y" ]; then
  "$EMU" -license accept                                   # ① 你本人接受 HarmonyOS 软件服务协议
  "$EMU" -install -deviceType phone -osVersion "HarmonyOS 6.1.1(24)"  # ② 下载系统镜像（数 GB）
  "$EMU" -create OrangeCloudAVD -deviceType phone -osVersion "HarmonyOS 6.1.1(24)"
  "$EMU" -start OrangeCloudAVD &                            # 启动（GUI，可能要账号登录）
  echo "   等待模拟器就绪（首启动约 1-3 分钟）…"
  until "$HDC" list targets | grep -qv "Empty"; do sleep 5; done
fi

echo "==== 2. 签名（需在 DevEco 里登录华为账号自动签名，或填 build-profile.json5 signingConfigs）===="
echo "   命令行无法代做：请在 DevEco Studio → File → Project Structure → Signing Configs"
echo "   勾 'Automatically generate signature'（登录华为账号），或手动填证书。"
read -p "   已配好签名？回车继续打签名包… " _
"$NODE" "$HVIGOR" --mode module -p module=entry@default -p product=default \
  -p buildMode=debug assembleHap --no-daemon

echo "==== 3. 安装并拉起 ===="
HAP=$(ls entry/build/default/outputs/default/*.hap | head -1)
"$HDC" install "$HAP"
"$HDC" shell aa start -a EntryAbility -b ltd.zhe.orange_cloud

cat <<'CHECK'
==== 4. 人工验收清单（在设备上逐项看）====
[ ] OAuth：点「使用 Cloudflare 登录」→ 浏览器授权 → o-c.do → 自动跳回 App、进主界面
[ ] 五 Tab（总览/域名/开发/存储/设置）天色背景 + 玻璃卡片观感
[ ] 概览页：24h 请求山脊 sparkline，太阳落在当前钟点
[ ] 分析页：Canvas 山脊地形 + 缓存命中太阳弧仪表
[ ] DNS/WAF/Workers/R2/D1/KV 等各模块 CRUD 实操
[ ] 存储→R2：点上传→选文件（picker 弹窗）→二进制对象上传成功
[ ] 桌面长按加服务卡：天窗 2×2 + 山脊 2×4，看快照渲染、点按拉起 App
[ ] Zero Trust：新建 Access 应用 / Gateway 规则
CHECK
echo "验收脚本结束。"
