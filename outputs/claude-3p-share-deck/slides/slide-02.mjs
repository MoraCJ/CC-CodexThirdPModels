import { S, bg, footer, kicker, labelBox, rect, subtitle, text, title } from "./common.mjs";

export async function slide02(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "problem");
  title(slide, ctx, "CLI 可用，不等于 Desktop 全部可用。", 84, 36, 900);
  subtitle(slide, ctx, "这次问题不是单点 API 故障，而是 Desktop 新架构下的多层调用链差异。", 58, 178, 780, 32);

  const xs = [70, 446, 822];
  const heads = ["Desktop 3P", "Code host", "Cowork"];
  const notes = [
    "Electron 网络栈\n读取 configLibrary\n要求 HTTPS + 可信证书",
    "调用本地 Claude Code binary\n读取 ~/.claude/settings.json\n版本目录由 Desktop 决定",
    "host loop / VM 侧调用\n环境变量继承不完整\n证书失败会表现成 server busy",
  ];
  const colors = [S.pale, "#EFF6FF", S.sand];
  xs.forEach((x, idx) => {
    rect(slide, ctx, x, 258, 300, 260, colors[idx], { line: ctx.line({ color: S.muted, width: 1 }) });
    text(slide, ctx, heads[idx], x + 24, 284, 220, 32, { size: 24, bold: true, face: "Avenir Next" });
    text(slide, ctx, notes[idx], x + 24, 344, 238, 110, { size: 15, color: S.soft });
    labelBox(slide, ctx, idx === 0 ? "配置层" : idx === 1 ? "执行层" : "协作层", x + 24, 466, 112, 34, S.dark, {
      color: S.white,
      size: 12,
      bold: true,
    });
  });

  text(slide, ctx, "判断原则：日志比 UI 文案更可信，代理日志比“模型名称显示”更可信。", 90, 566, 960, 34, {
    size: 20,
    color: S.ink,
    bold: true,
  });
  footer(slide, ctx, 2, "Problem framing");
  return slide;
}
