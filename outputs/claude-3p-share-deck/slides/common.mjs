export const S = {
  bg: "#F7FAFC",
  ink: "#10202A",
  soft: "#60717E",
  muted: "#D8E2E8",
  line: "#B7C7D1",
  teal: "#176B87",
  green: "#2A9D8F",
  gold: "#D89135",
  red: "#C94A4A",
  dark: "#0E2532",
  white: "#FFFFFF",
  pale: "#EAF5F7",
  sand: "#F7EFE2",
  blue: "#2F6FED",
};

export function text(slide, ctx, value, x, y, w, h, opts = {}) {
  return ctx.addText(slide, {
    text: String(value ?? ""),
    left: x,
    top: y,
    width: w,
    height: h,
    fontSize: opts.size ?? 18,
    color: opts.color ?? S.ink,
    bold: Boolean(opts.bold),
    typeface: opts.face ?? "PingFang SC",
    align: opts.align ?? "left",
    valign: opts.valign ?? "top",
    fill: opts.fill ?? "#00000000",
    line: opts.line ?? ctx.line(),
    insets: opts.insets ?? { left: 0, right: 0, top: 0, bottom: 0 },
    name: opts.name,
  });
}

export function rect(slide, ctx, x, y, w, h, fill, opts = {}) {
  return ctx.addShape(slide, {
    left: x,
    top: y,
    width: w,
    height: h,
    geometry: "rect",
    fill,
    line: opts.line ?? ctx.line(),
    name: opts.name,
  });
}

export function rule(slide, ctx, x, y, w, color = S.line, weight = 1) {
  rect(slide, ctx, x, y, w, weight, color);
}

export function bg(slide, ctx) {
  rect(slide, ctx, 0, 0, 1280, 720, S.bg);
}

export function kicker(slide, ctx, label, x = 58, y = 46) {
  rect(slide, ctx, x, y + 4, 10, 10, S.teal);
  text(slide, ctx, label.toUpperCase().split("").join(" "), x + 22, y, 520, 18, {
    size: 9.5,
    color: S.soft,
    bold: true,
  });
}

export function title(slide, ctx, value, y = 82, size = 36, w = 920) {
  text(slide, ctx, value, 58, y, w, 72, {
    size,
    color: S.ink,
    bold: true,
    face: "Avenir Next",
  });
}

export function subtitle(slide, ctx, value, x, y, w, h, size = 16) {
  text(slide, ctx, value, x, y, w, h, {
    size,
    color: S.soft,
    face: "PingFang SC",
  });
}

export function footer(slide, ctx, page, label) {
  rule(slide, ctx, 58, 676, 1164, S.muted, 1);
  text(slide, ctx, label, 58, 686, 850, 18, { size: 8, color: S.soft });
  text(slide, ctx, String(page).padStart(2, "0"), 1174, 682, 48, 22, {
    size: 12,
    color: S.soft,
    bold: true,
    align: "right",
    face: "Avenir Next",
  });
}

export function labelBox(slide, ctx, value, x, y, w, h, fill, opts = {}) {
  rect(slide, ctx, x, y, w, h, fill, {
    line: opts.line ?? ctx.line({ color: opts.stroke ?? "#00000000", width: opts.stroke ? 1 : 0 }),
  });
  const padY = h <= 42 ? 8 : 16;
  text(slide, ctx, value, x + 16, y + padY, w - 32, h - padY * 2, {
    size: opts.size ?? 14,
    color: opts.color ?? S.ink,
    bold: Boolean(opts.bold),
    valign: "mid",
  });
}

export function metric(slide, ctx, value, label, note, x, y, color = S.teal) {
  rule(slide, ctx, x, y, 2, color, 56);
  text(slide, ctx, value, x + 14, y - 4, 180, 34, {
    size: 28,
    color: S.ink,
    bold: true,
    face: "Avenir Next",
  });
  text(slide, ctx, label, x + 14, y + 36, 180, 18, {
    size: 9.5,
    color: S.soft,
    bold: true,
  });
  text(slide, ctx, note, x + 14, y + 54, 180, 28, {
    size: 8.2,
    color: S.soft,
  });
}

export function flowArrow(slide, ctx, x1, y, x2, color = S.teal) {
  const w = Math.max(1, x2 - x1 - 16);
  rect(slide, ctx, x1, y, w, 2, color);
  text(slide, ctx, ">", x2 - 18, y - 11, 20, 22, {
    size: 18,
    color,
    bold: true,
    align: "center",
    face: "Avenir Next",
  });
}

export function tableRow(slide, ctx, cells, x, y, widths, h, fill, opts = {}) {
  let xx = x;
  cells.forEach((cell, idx) => {
    rect(slide, ctx, xx, y, widths[idx], h, fill, {
      line: ctx.line({ color: opts.lineColor ?? S.muted, width: 1 }),
    });
    text(slide, ctx, cell, xx + 10, y + 8, widths[idx] - 20, h - 12, {
      size: opts.size ?? 11,
      color: opts.color ?? S.ink,
      bold: Boolean(opts.bold),
      valign: "mid",
    });
    xx += widths[idx];
  });
}
