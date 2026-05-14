import { S, bg, footer, kicker, rect, tableRow, text, title } from "./common.mjs";

export async function slide08(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "failure paths");
  title(slide, ctx, "失败路径也有价值：它们定义了边界。", 84, 36, 900);

  const x = 72;
  const y = 238;
  const widths = [220, 300, 430];
  tableRow(slide, ctx, ["失败路径", "表象", "正确处理"], x, y, widths, 42, S.dark, {
    color: S.white,
    bold: true,
    size: 13,
  });
  const rows = [
    ["Desktop 直连 Ark", "CLI 可用但 App 503/证书错", "改为本机 HTTPS 代理"],
    ["只配 CLI CA", "Desktop 仍报 cert authority", "CA 加入 Keychain"],
    ["保留 ANTHROPIC_MODEL", "选择槽位后仍被覆盖", "删除强制模型变量"],
    ["无 .verified", "host 目录被 repair 清空", "先 touch .verified 再放 binary"],
    ["downloads 超时", "VM boot / bash proxy 失败", "网络白名单、代理或离线缓存"],
  ];
  rows.forEach((row, idx) => {
    tableRow(slide, ctx, row, x, y + 42 + idx * 60, widths, 60, idx % 2 ? "#F8FBFC" : S.white, {
      size: 12,
    });
  });

  rect(slide, ctx, 72, 590, 1060, 48, "#EEF5F8");
  text(slide, ctx, "判断优先级：proxy log 200 > Desktop health healthy > UI 模型显示。", 94, 604, 760, 22, {
    size: 14,
    color: S.teal,
    bold: true,
  });
  footer(slide, ctx, 8, "Known failure modes");
  return slide;
}
