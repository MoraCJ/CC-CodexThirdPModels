import { S, bg, footer, kicker, labelBox, rect, subtitle, text, title } from "./common.mjs";

export async function slide07(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "cowork");
  title(slide, ctx, "Cowork 的关键不是换模型，而是让 host loop 信任 CA。", 84, 34, 1000);
  subtitle(slide, ctx, "Code 可以对话、Cowork 显示 server is busy 时，真正错误可能是 SSL certificate verification failed。", 58, 176, 960, 32);

  rect(slide, ctx, 80, 258, 430, 250, "#FFF4F2", { line: ctx.line({ color: "#F0C9C4", width: 1 }) });
  text(slide, ctx, "Before", 110, 286, 120, 26, { size: 20, bold: true, color: S.red, face: "Avenir Next" });
  text(slide, ctx, "Cowork -> host loop -> proxy\n\n环境变量继承不完整\nNODE_EXTRA_CA_CERTS 不可靠\nUI 只显示 server is busy", 110, 338, 330, 120, {
    size: 15,
    color: S.ink,
  });

  rect(slide, ctx, 590, 258, 500, 250, S.pale, { line: ctx.line({ color: S.muted, width: 1 }) });
  text(slide, ctx, "After", 620, 286, 120, 26, { size: 20, bold: true, color: S.green, face: "Avenir Next" });
  text(slide, ctx, "host binary -> claude-ca-launcher\n\n强制注入：\nNODE_USE_SYSTEM_CA=1\nNODE_EXTRA_CA_CERTS=/path/to/ca.crt\nSSL_CERT_FILE=/path/to/ca.crt", 620, 338, 390, 132, {
    size: 15,
    color: S.ink,
  });

  labelBox(slide, ctx, ".verified + 正确版本目录\n防止 Desktop repair 清空手工 binary", 228, 548, 760, 72, S.dark, {
    color: S.white,
    bold: true,
    size: 15,
  });
  footer(slide, ctx, 7, "Cowork certificate fix");
  return slide;
}
