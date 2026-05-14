import { S, bg, footer, kicker, rect, text, title } from "./common.mjs";

export async function slide06(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "runbook");
  title(slide, ctx, "macOS 配置顺序要固定，排障才会收敛。", 84, 36, 950);

  const steps = [
    ["1", "代理", "启动 127.0.0.1:38443"],
    ["2", "证书", "CA 写入 Keychain"],
    ["3", "Desktop", "配置 third-party inference"],
    ["4", "CLI", "settings 只保留 env"],
    ["5", "Host", "按日志版本建 .verified"],
    ["6", "Cowork", "必要时使用 launcher"],
    ["7", "验证", "看 health / main.log / proxy.log"],
  ];

  const x0 = 78;
  const y0 = 264;
  steps.forEach((step, idx) => {
    const x = x0 + idx * 160;
    rect(slide, ctx, x, y0, 82, 82, idx % 2 ? S.pale : S.dark);
    text(slide, ctx, step[0], x + 22, y0 + 14, 38, 38, {
      size: 30,
      color: idx % 2 ? S.teal : S.white,
      bold: true,
      align: "center",
      face: "Avenir Next",
    });
    text(slide, ctx, step[1], x - 18, y0 + 104, 118, 24, {
      size: 16,
      color: S.ink,
      bold: true,
      align: "center",
    });
    text(slide, ctx, step[2], x - 28, y0 + 136, 138, 48, {
      size: 11.5,
      color: S.soft,
      align: "center",
    });
    if (idx < steps.length - 1) {
      rect(slide, ctx, x + 94, y0 + 40, 48, 2, S.line);
      text(slide, ctx, ">", x + 136, y0 + 29, 18, 22, { size: 18, color: S.line, bold: true });
    }
  });

  text(slide, ctx, "顺序错了会出现“每层看起来都像问题”的假象；固定顺序能把问题定位到证书、模型、host 或网络下载。", 100, 548, 980, 32, {
    size: 18,
    color: S.ink,
    bold: true,
  });
  footer(slide, ctx, 6, "macOS setup order");
  return slide;
}
