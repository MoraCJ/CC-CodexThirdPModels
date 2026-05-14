import { S, bg, flowArrow, footer, kicker, labelBox, rect, subtitle, text, title } from "./common.mjs";

export async function slide04(presentation, ctx) {
  const slide = presentation.slides.add();
  bg(slide, ctx);
  kicker(slide, ctx, "certificate");
  title(slide, ctx, "macOS 上的关键动作：让证书被系统信任。", 84, 36, 900);
  subtitle(slide, ctx, "只让 CLI 信任 CA 不够；Desktop 的 Electron 网络栈和 Cowork host loop 也要能建立可信链。", 58, 178, 900, 32);

  const y = 286;
  labelBox(slide, ctx, "本地 CA\nca.crt", 82, y, 170, 86, S.white, { stroke: S.muted, bold: true, size: 16 });
  flowArrow(slide, ctx, 272, y + 42, 378, S.teal);
  labelBox(slide, ctx, "Keychain\nSSL trust", 394, y, 190, 86, S.pale, { stroke: S.muted, bold: true, size: 16 });
  flowArrow(slide, ctx, 604, y + 42, 710, S.teal);
  labelBox(slide, ctx, "Electron\nDesktop 3P", 724, y - 48, 190, 78, S.white, { stroke: S.muted, bold: true, size: 15 });
  labelBox(slide, ctx, "host loop\nCowork", 724, y + 56, 190, 78, S.white, { stroke: S.muted, bold: true, size: 15 });
  flowArrow(slide, ctx, 932, y + 42, 1040, S.green);
  labelBox(slide, ctx, "Local proxy\nHTTPS OK", 1052, y, 150, 86, S.dark, {
    color: S.white,
    bold: true,
    size: 15,
  });

  rect(slide, ctx, 96, 500, 1000, 78, S.sand);
  text(slide, ctx, "SSH 限制", 120, 516, 120, 24, { size: 16, bold: true, color: S.gold });
  text(
    slide,
    ctx,
    "远程 SSH 下写 System keychain 可能被 macOS 授权拦截；需要目标 Mac 本机交互式 sudo，或由 MDM / 配置描述文件下发。",
    242,
    514,
    780,
    42,
    { size: 14, color: S.ink }
  );
  footer(slide, ctx, 4, "macOS certificate trust");
  return slide;
}
