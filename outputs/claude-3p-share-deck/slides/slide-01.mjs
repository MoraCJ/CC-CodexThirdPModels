import { S, bg, footer, metric, rect, rule, subtitle, text } from "./common.mjs";

export async function slide01(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  rect(slide, ctx, 0, 0, 1280, 720, S.bg);
  rect(slide, ctx, 58, 52, 6, 64, S.teal);
  text(slide, ctx, "Claude Code Desktop", 82, 54, 420, 22, {
    size: 12,
    color: S.soft,
    bold: true,
    face: "Avenir Next",
  });
  text(slide, ctx, "第三方 API 接入复盘", 58, 170, 760, 128, {
    size: 52,
    color: S.ink,
    bold: true,
    face: "Avenir Next",
  });
  subtitle(
    slide,
    ctx,
    "本机 HTTPS 代理 + macOS 证书信任 + Claude 槽位映射，解决 CLI 可用但 App / Cowork 不稳定的问题。",
    60,
    322,
    700,
    58,
    18
  );
  rect(slide, ctx, 850, 0, 430, 720, S.dark);
  text(slide, ctx, "最终链路", 900, 86, 220, 28, {
    size: 14,
    color: "#A7CBD6",
    bold: true,
  });
  text(slide, ctx, "Desktop / Code / Cowork\n统一进本机 HTTPS 代理\n再转发到 Ark", 900, 148, 292, 176, {
    size: 26,
    color: S.white,
    bold: true,
    face: "Avenir Next",
  });
  rule(slide, ctx, 900, 342, 260, "#315363", 1);
  text(slide, ctx, "2026-05-14\n可分享版", 900, 376, 220, 62, {
    size: 14,
    color: "#C7D8DF",
  });
  metric(slide, ctx, "01", "入口统一", "Desktop / CLI 同源", 58, 518, S.teal);
  metric(slide, ctx, "02", "证书可信", "Keychain + launcher", 328, 518, S.green);
  metric(slide, ctx, "03", "槽位映射", "Claude 名称保留", 598, 518, S.gold);
  footer(slide, ctx, 1, "Claude Code Desktop third-party inference sharing deck");
  return slide;
}
