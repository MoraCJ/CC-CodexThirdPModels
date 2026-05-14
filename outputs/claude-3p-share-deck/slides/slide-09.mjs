import { S, bg, footer, kicker, labelBox, rect, text, title } from "./common.mjs";

export async function slide09(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "verification");
  title(slide, ctx, "验收只看四类信号。", 84, 36, 700);

  const items = [
    ["health", "curl https://127.0.0.1:38443/health", "系统信任后不带 --cacert 也成功"],
    ["Desktop", "ConfigHealth recomputed", "state: healthy / provider: gateway"],
    ["proxy", "POST /v1/messages -> 200", "模型映射日志能看到真实上游模型"],
    ["Cowork", "极简环境调用 launcher", "能回复 ok，不再报 SSL certificate"],
  ];
  items.forEach((item, idx) => {
    const y = 218 + idx * 94;
    rect(slide, ctx, 82, y, 86, 56, idx % 2 ? S.pale : S.dark);
    text(slide, ctx, String(idx + 1).padStart(2, "0"), 104, y + 10, 42, 28, {
      size: 24,
      color: idx % 2 ? S.teal : S.white,
      bold: true,
      face: "Avenir Next",
      align: "center",
    });
    text(slide, ctx, item[0], 198, y + 2, 120, 22, { size: 16, bold: true, color: S.ink });
    text(slide, ctx, item[1], 198, y + 28, 360, 18, { size: 11.5, color: S.soft });
    text(slide, ctx, item[2], 610, y + 18, 430, 22, { size: 14, color: S.ink, bold: true });
  });

  labelBox(slide, ctx, "可复用原则：先统一入口，再处理证书，再做模型映射，最后处理 host/Cowork 特例。", 130, 602, 930, 64, S.dark, {
    color: S.white,
    bold: true,
    size: 15,
  });
  footer(slide, ctx, 9, "Verification checklist");
  return slide;
}
