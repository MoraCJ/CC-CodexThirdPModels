import { S, bg, flowArrow, footer, kicker, labelBox, rect, subtitle, text, title } from "./common.mjs";

export async function slide03(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "architecture");
  title(slide, ctx, "实现逻辑：所有入口先收敛，再做兼容。", 84, 36, 920);
  subtitle(slide, ctx, "不要让 Desktop、CLI、Cowork 各自直连上游；入口越分散，证书和模型映射越难排障。", 58, 178, 900, 32);

  const sourceX = 72;
  const rows = [
    ["Desktop 3P UI", "configLibrary"],
    ["Code host", "~/.claude/settings.json"],
    ["Cowork", "claude-ca-launcher"],
    ["CLI", "env only"],
  ];
  rows.forEach((row, idx) => {
    const y = 252 + idx * 78;
    labelBox(slide, ctx, `${row[0]}\n${row[1]}`, sourceX, y - 5, 250, 64, S.white, {
      stroke: S.muted,
      size: 13,
      bold: idx === 0,
    });
    flowArrow(slide, ctx, 335, y + 26, 430, S.teal);
  });

  rect(slide, ctx, 448, 282, 260, 216, S.dark);
  text(slide, ctx, "Local HTTPS proxy", 474, 306, 238, 62, {
    size: 24,
    color: S.white,
    bold: true,
    face: "Avenir Next",
  });
  text(slide, ctx, "https://127.0.0.1:38443\n\nTLS server cert\nmodel rewrite\nheader passthrough", 474, 372, 208, 92, {
    size: 14,
    color: "#D5E7ED",
  });
  flowArrow(slide, ctx, 724, 386, 834, S.green);

  rect(slide, ctx, 852, 292, 300, 196, S.pale, { line: ctx.line({ color: S.muted, width: 1 }) });
  text(slide, ctx, "Ark coding API", 880, 326, 220, 32, {
    size: 24,
    color: S.ink,
    bold: true,
    face: "Avenir Next",
  });
  text(slide, ctx, "https://ark.cn-beijing.volces.com/api/coding\n\nAnthropic-compatible protocol", 880, 382, 220, 72, {
    size: 14,
    color: S.soft,
  });

  rect(slide, ctx, 72, 586, 1080, 34, "#EEF5F8");
  text(slide, ctx, "模型显示名留在 Claude 槽位，真实上游模型只在代理里出现。", 92, 594, 680, 20, {
    size: 14,
    color: S.teal,
    bold: true,
  });
  footer(slide, ctx, 3, "Implementation diagram");
  return slide;
}
