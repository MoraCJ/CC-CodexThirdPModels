import { S, bg, footer, kicker, rect, tableRow, text, title } from "./common.mjs";

export async function slide05(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "model mapping");
  title(slide, ctx, "模型槽位保留 Claude 名称，代理再改写。", 84, 36, 980);

  text(slide, ctx, "这样 App 的模型选择、CLI 的默认槽位、上游真实模型三者不会互相覆盖。", 58, 178, 820, 30, {
    size: 16,
    color: S.soft,
  });

  const x = 92;
  const y = 258;
  const widths = [210, 300, 300, 190];
  tableRow(slide, ctx, ["槽位", "App/CLI 发送", "代理转发", "说明"], x, y, widths, 46, S.dark, {
    color: S.white,
    bold: true,
    size: 13,
  });
  tableRow(slide, ctx, ["Opus", "claude-opus-4-6", "glm-5.1", "大模型槽位"], x, y + 46, widths, 58, S.white, { size: 13 });
  tableRow(slide, ctx, ["Sonnet", "claude-sonnet-4-6", "kimi-k2.6", "默认/中模型"], x, y + 104, widths, 58, "#F8FBFC", { size: 13 });
  tableRow(slide, ctx, ["Haiku", "claude-haiku-4-5", "doubao-seed-2.0-pro", "小模型槽位"], x, y + 162, widths, 58, S.white, { size: 13 });

  rect(slide, ctx, 92, 510, 1000, 88, "#EEF5F8");
  text(slide, ctx, "不要保留 ANTHROPIC_MODEL，也不要再叠加 modelOverrides。", 118, 526, 620, 22, {
    size: 17,
    color: S.teal,
    bold: true,
  });
  text(slide, ctx, "否则 App 里选 Sonnet / Haiku，实际也可能被强制打到同一个模型。", 118, 552, 760, 24, {
    size: 12,
    color: S.soft,
  });
  footer(slide, ctx, 5, "Slot mapping policy");
  return slide;
}
