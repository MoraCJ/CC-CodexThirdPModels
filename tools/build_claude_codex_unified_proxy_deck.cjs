#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const PptxGenJS = require("/Users/chjia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pptxgenjs");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "docs", "claude-codex-unified-proxy-intro.pptx");

const pptx = new PptxGenJS();
pptx.layout = "LAYOUT_WIDE";
pptx.author = "CJ / Codex";
pptx.company = "CJ";
pptx.subject = "Claude + Codex unified local proxy handoff";
pptx.title = "Claude + Codex 统一代理接入复盘";
pptx.lang = "zh-CN";
pptx.theme = {
  headFontFace: "Aptos Display",
  bodyFontFace: "PingFang SC",
  lang: "zh-CN",
};
pptx.defineLayout({ name: "CJ_WIDE", width: 13.333, height: 7.5 });
pptx.layout = "CJ_WIDE";
pptx.margin = 0;

const S = {
  bg: "F7FAFC",
  ink: "10202A",
  soft: "60717E",
  muted: "D8E2E8",
  line: "B7C7D1",
  teal: "176B87",
  green: "2A9D8F",
  gold: "D89135",
  red: "C94A4A",
  dark: "0E2532",
  white: "FFFFFF",
  pale: "EAF5F7",
  sand: "F7EFE2",
  blue: "2F6FED",
};

function bg(slide) {
  slide.background = { color: S.bg };
  rect(slide, 0, 0, 13.333, 7.5, S.bg);
}

function rect(slide, x, y, w, h, fill, line = fill, width = 0) {
  slide.addShape(pptx.ShapeType.rect, {
    x,
    y,
    w,
    h,
    fill: { color: fill },
    line: { color: line, transparency: width ? 0 : 100, width },
  });
}

function rule(slide, x, y, w, color = S.muted, h = 0.012) {
  rect(slide, x, y, w, h, color, color, 0);
}

function text(slide, value, x, y, w, h, opts = {}) {
  slide.addText(String(value ?? ""), {
    x,
    y,
    w,
    h,
    margin: opts.margin ?? 0,
    fontFace: opts.face || "PingFang SC",
    fontSize: opts.size || 12,
    color: opts.color || S.ink,
    bold: Boolean(opts.bold),
    align: opts.align || "left",
    valign: opts.valign || "top",
    breakLine: false,
    fit: "shrink",
    paraSpaceAfterPt: opts.after ?? 0,
    breakLineOnHyphen: false,
  });
}

function kicker(slide, label) {
  rect(slide, 0.58, 0.48, 0.1, 0.1, S.teal);
  text(slide, label.toUpperCase().split("").join(" "), 0.82, 0.43, 5.5, 0.24, {
    size: 8.5,
    color: S.soft,
    bold: true,
    face: "Aptos",
  });
}

function title(slide, value, y = 0.86, size = 31, w = 8.6) {
  text(slide, value, 0.58, y, w, 0.7, {
    size,
    bold: true,
    color: S.ink,
    face: "Aptos Display",
  });
}

function subtitle(slide, value, x, y, w, h, size = 14) {
  text(slide, value, x, y, w, h, { size, color: S.soft });
}

function footer(slide, page, label) {
  rule(slide, 0.58, 7.02, 12.1);
  text(slide, label, 0.58, 7.13, 8.8, 0.18, { size: 7.5, color: S.soft, face: "Aptos" });
  text(slide, String(page).padStart(2, "0"), 12.1, 7.08, 0.62, 0.24, {
    size: 10,
    color: S.soft,
    bold: true,
    align: "right",
    face: "Aptos",
  });
}

function tag(slide, value, x, y, w, fill = S.dark, color = S.white) {
  rect(slide, x, y, w, 0.34, fill, fill, 0);
  text(slide, value, x + 0.13, y + 0.08, w - 0.26, 0.16, {
    size: 8.5,
    color,
    bold: true,
    valign: "mid",
  });
}

function arrow(slide, x1, y, x2, color = S.teal) {
  const w = Math.max(0.2, x2 - x1 - 0.18);
  rect(slide, x1, y, w, 0.025, color, color, 0);
  text(slide, ">", x2 - 0.18, y - 0.12, 0.2, 0.26, {
    size: 16,
    color,
    bold: true,
    align: "center",
    face: "Aptos",
  });
}

function card(slide, x, y, w, h, head, body, accent = S.teal, fill = S.white) {
  rect(slide, x, y, w, h, fill, S.muted, 1);
  rect(slide, x, y, 0.05, h, accent, accent, 0);
  text(slide, head, x + 0.22, y + 0.2, w - 0.4, 0.28, {
    size: 14,
    bold: true,
    color: S.ink,
  });
  text(slide, body, x + 0.22, y + 0.62, w - 0.42, h - 0.8, {
    size: 10.5,
    color: S.soft,
  });
}

function table(slide, x, y, widths, rowH, rows, headerFill = S.pale) {
  rows.forEach((row, r) => {
    let xx = x;
    row.forEach((cell, c) => {
      const fill = r === 0 ? headerFill : r % 2 ? S.white : "F2F7F9";
      rect(slide, xx, y + r * rowH, widths[c], rowH, fill, S.muted, 0.7);
      text(slide, cell, xx + 0.08, y + r * rowH + 0.08, widths[c] - 0.16, rowH - 0.14, {
        size: r === 0 ? 8.8 : 8.3,
        bold: r === 0,
        color: r === 0 ? S.ink : S.soft,
        valign: "mid",
      });
      xx += widths[c];
    });
  });
}

function addSlide01() {
  const slide = pptx.addSlide();
  bg(slide);
  rect(slide, 0.58, 0.54, 0.07, 0.7, S.teal);
  text(slide, "Claude Code + Codex", 0.82, 0.56, 4.4, 0.24, {
    size: 12,
    color: S.soft,
    bold: true,
    face: "Aptos",
  });
  text(slide, "统一代理接入复盘", 0.58, 1.72, 7.5, 1.15, {
    size: 42,
    bold: true,
    color: S.ink,
    face: "Aptos Display",
  });
  subtitle(
    slide,
    "把 Claude 的本机 HTTPS 代理扩展为统一兼容层：Claude 保留槽位映射，Codex 使用真实模型名与 profiles。",
    0.6,
    3.25,
    7.2,
    0.56,
    14.5
  );
  rect(slide, 8.85, 0, 4.48, 7.5, S.dark);
  text(slide, "最终状态", 9.35, 0.88, 2.2, 0.28, { size: 13, color: "A7CBD6", bold: true });
  text(slide, "Claude / Codex\n共用 38443\n一个证书链\n一个运行入口", 9.35, 1.48, 3.0, 1.9, {
    size: 27,
    bold: true,
    color: S.white,
    face: "Aptos Display",
  });
  rule(slide, 9.35, 3.72, 2.7, "315363");
  text(slide, "2026-05-14\nHandoff 分享版", 9.35, 4.06, 2.3, 0.6, { size: 12, color: "C7D8DF" });
  card(slide, 0.58, 5.3, 2.1, 0.78, "01 入口统一", "https://127.0.0.1:38443", S.teal, S.pale);
  card(slide, 3.1, 5.3, 2.1, 0.78, "02 协议转换", "Responses -> Chat", S.green, S.pale);
  card(slide, 5.62, 5.3, 2.1, 0.78, "03 多模型", "Codex profiles", S.gold, S.sand);
  footer(slide, 1, "Unified local proxy overview");
}

function addSlide02() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "handoff");
  title(slide, "这次交接的核心结论。", 0.86, 31, 7.4);
  subtitle(slide, "旧 handoff 的 Claude-only 成功经验仍然有效，但现在入口、验证和模型策略已经扩展到 Codex。", 0.6, 1.78, 8.2, 0.4, 13);
  const items = [
    ["只留一个本机入口", "Claude Desktop、Claude CLI、Codex CLI/App 都经由 38443 进入本机 HTTPS 代理。", S.teal],
    ["Claude 槽位继续映射", "Opus / Sonnet / Haiku 保留给 Claude 侧兼容，代理映射到真实 Ark 模型。", S.green],
    ["Codex 用真实模型名", "doubao、kimi、glm 直接写进 profile，切换更清楚，避免再做一层假名。", S.gold],
    ["验证看行为信号", "health、日志 200、profile 回复、tool call 可用，比 UI 里的模型显示更可靠。", S.blue],
  ];
  items.forEach((item, i) => {
    const x = i % 2 === 0 ? 0.72 : 6.72;
    const y = i < 2 ? 2.58 : 4.58;
    card(slide, x, y, 5.05, 1.3, item[0], item[1], item[2]);
  });
  footer(slide, 2, "Handoff summary");
}

function addSlide03() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "architecture");
  title(slide, "从两个代理，收敛成一个兼容层。", 0.86, 31, 8.6);

  text(slide, "合并前", 1.05, 1.88, 2.0, 0.3, { size: 16, bold: true });
  rect(slide, 0.82, 2.28, 4.78, 3.2, S.white, S.muted, 1);
  card(slide, 1.12, 2.62, 1.78, 0.88, "Claude", "38443\n/api/coding", S.teal, S.pale);
  card(slide, 3.12, 2.62, 1.78, 0.88, "Codex", "38444\n/api/coding/v3", S.red, "FCEEEE");
  text(slide, "两个进程、两个 LaunchAgent、两套日志和健康检查。\n排障时容易先确认错对象。", 1.1, 4.02, 3.95, 0.72, {
    size: 11.5,
    color: S.soft,
  });

  text(slide, "合并后", 7.0, 1.88, 2.0, 0.3, { size: 16, bold: true });
  rect(slide, 6.54, 2.28, 4.78, 3.2, S.white, S.muted, 1);
  card(slide, 7.05, 2.62, 3.65, 0.98, "claude-local-proxy", "https://127.0.0.1:38443", S.green, S.pale);
  text(slide, "一个进程托管两类协议：Claude 透传 + 槽位映射，Codex Responses 转 Chat Completions。", 7.05, 4.04, 3.75, 0.7, {
    size: 11.5,
    color: S.soft,
  });

  arrow(slide, 5.75, 3.75, 6.32, S.teal);
  tag(slide, "保留旧 38444 文件作回滚参考，但当前不监听", 3.72, 5.95, 5.9, S.dark);
  footer(slide, 3, "Before and after architecture");
}

function addSlide04() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "routing");
  title(slide, "统一代理按路径分流，而不是按工具分流。", 0.86, 31, 9.2);
  rect(slide, 5.0, 2.8, 3.3, 1.08, S.dark, S.dark, 0);
  text(slide, "claude-local-proxy/server.js", 5.28, 3.08, 2.75, 0.28, { size: 15, bold: true, color: S.white });
  tag(slide, "LaunchAgent: com.cj.claude-local-https-proxy", 4.68, 4.08, 4.02, S.pale, S.teal);

  card(slide, 0.82, 1.92, 3.22, 0.96, "Claude Desktop / CLI", "POST /v1/messages\nPOST /v1/messages/count_tokens", S.teal, S.white);
  card(slide, 0.82, 4.24, 3.22, 0.96, "Codex CLI / App", "POST /v1/responses", S.gold, S.white);
  card(slide, 9.18, 1.92, 3.2, 0.96, "Ark coding", "https://.../api/coding", S.teal, S.white);
  card(slide, 9.18, 4.24, 3.2, 0.96, "Ark coding v3", "https://.../api/coding/v3/chat/completions", S.gold, S.white);

  arrow(slide, 4.08, 2.46, 4.88, S.teal);
  arrow(slide, 8.36, 2.46, 9.08, S.teal);
  arrow(slide, 4.08, 4.78, 4.88, S.gold);
  arrow(slide, 8.36, 4.78, 9.08, S.gold);

  text(slide, "Claude 分支：透传请求头与 body，只替换模型名。", 5.1, 1.92, 3.0, 0.3, { size: 11.5, color: S.soft });
  text(slide, "Codex 分支：解析 Responses API，再组装 Chat Completions 请求。", 4.9, 5.22, 3.65, 0.36, { size: 11.5, color: S.soft });
  footer(slide, 4, "Path-based routing");
}

function addSlide05() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "translation");
  title(slide, "Codex 的关键是 Responses API 兼容。", 0.86, 31, 8.5);
  subtitle(slide, "统一代理没有要求 Ark 原生支持 Responses API，而是在本机完成最小协议桥接。", 0.6, 1.74, 8.1, 0.36, 13);
  const steps = [
    ["1", "读入", "input / instructions / tools"],
    ["2", "转换消息", "developer -> system\nfunction_call_output -> tool"],
    ["3", "转换工具", "Responses tools -> chat tools"],
    ["4", "请求上游", "/chat/completions"],
    ["5", "还原响应", "message / function_call / usage"],
  ];
  steps.forEach((s, i) => {
    const x = 0.72 + i * 2.48;
    rect(slide, x, 2.72, 1.98, 1.72, i === 3 ? S.sand : S.white, S.muted, 1);
    text(slide, s[0], x + 0.18, 2.92, 0.38, 0.38, { size: 18, bold: true, color: i === 3 ? S.gold : S.teal, face: "Aptos" });
    text(slide, s[1], x + 0.58, 2.96, 1.1, 0.26, { size: 15, bold: true });
    text(slide, s[2], x + 0.18, 3.48, 1.56, 0.5, { size: 9.7, color: S.soft });
    if (i < steps.length - 1) arrow(slide, x + 2.05, 3.52, x + 2.36, i === 3 ? S.gold : S.teal);
  });
  tag(slide, "当前验证：Codex 默认模型、三个 profile、tool call 均可用", 2.54, 5.58, 8.1, S.dark);
  footer(slide, 5, "Responses API bridge");
}

function addSlide06() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "models");
  title(slide, "模型策略：Claude 映射，Codex 直连真实模型名。", 0.86, 30, 10.2);
  table(
    slide,
    0.62,
    1.9,
    [2.05, 3.0, 3.05, 3.1],
    0.56,
    [
      ["工具", "客户端模型名", "代理/上游模型名", "定位"],
      ["Claude", "claude-opus-4-6", "glm-5.1", "高质量推理"],
      ["Claude", "claude-sonnet-4-6", "kimi-k2.6", "默认主力"],
      ["Claude", "claude-haiku-4-5", "doubao-seed-2.0-pro", "快速任务"],
      ["Codex ark-doubao", "doubao-seed-2.0-pro", "doubao-seed-2.0-pro", "默认/快速"],
      ["Codex ark-kimi", "kimi-k2.6", "kimi-k2.6", "复杂编码"],
      ["Codex ark-glm", "glm-5.1", "glm-5.1", "高质量推理"],
    ]
  );
  text(slide, "建议：Codex 没必要模仿 Claude 的槽位名，真实模型名更利于排障、日志阅读和 profile 切换。", 0.9, 6.05, 10.9, 0.34, {
    size: 14,
    bold: true,
    color: S.ink,
  });
  footer(slide, 6, "Model strategy");
}

function addSlide07() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "codex config");
  title(slide, "Codex 用 provider + profiles 承载多模型。", 0.86, 31, 9.2);
  rect(slide, 0.72, 1.92, 6.36, 3.78, S.dark, S.dark, 0);
  text(
    slide,
    `model_provider = "ark-coding"\nmodel = "doubao-seed-2.0-pro"\n\n[model_providers.ark-coding]\nwire_api = "responses"\nbase_url = "https://127.0.0.1:38443/v1"\nrequires_openai_auth = true\n\n[profiles.ark-kimi]\nmodel = "kimi-k2.6"`,
    1.04,
    2.26,
    5.68,
    2.9,
    { size: 11.4, color: S.white, face: "Menlo" }
  );
  card(slide, 7.66, 2.04, 4.2, 0.86, "默认模型", "doubao-seed-2.0-pro，medium reasoning", S.gold, S.white);
  card(slide, 7.66, 3.18, 4.2, 0.86, "编码 profile", "ark-kimi -> kimi-k2.6，high reasoning", S.green, S.white);
  card(slide, 7.66, 4.32, 4.2, 0.86, "推理 profile", "ark-glm -> glm-5.1，high reasoning", S.teal, S.white);
  tag(slide, "切换命令：codex -p ark-doubao / ark-kimi / ark-glm", 2.08, 6.18, 8.95, S.pale, S.teal);
  footer(slide, 7, "Codex provider profiles");
}

function addSlide08() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "verification");
  title(slide, "验收矩阵已经覆盖入口、模型与工具调用。", 0.86, 31, 9.6);
  table(
    slide,
    0.75,
    1.82,
    [2.3, 7.4, 1.25],
    0.58,
    [
      ["检查项", "成功信号", "状态"],
      ["端口", "lsof 显示 127.0.0.1:38443 LISTEN；38444 不监听", "OK"],
      ["健康检查", "curl -sk https://127.0.0.1:38443/health 返回 ok + upstream 信息", "OK"],
      ["Claude", "/v1/messages 200；日志出现 claude-haiku-4-5 -> doubao-seed-2.0-pro", "OK"],
      ["Codex 默认", "doubao-seed-2.0-pro 可正常回复", "OK"],
      ["Codex profiles", "ark-doubao / ark-kimi / ark-glm 均可用", "OK"],
      ["Tool call", "pwd 等工具调用闭环成功", "OK"],
    ],
    S.pale
  );
  footer(slide, 8, "Verification matrix");
}

function addSlide09() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "operations");
  title(slide, "运行手册关注四件事：进程、端口、日志、配置。", 0.86, 31, 9.8);
  const ops = [
    ["LaunchAgent", "launchctl print / kickstart"],
    ["端口", "lsof -nP -iTCP:38443"],
    ["健康", "curl -sk /health /healthz"],
    ["日志", "proxy.log / proxy.err.log"],
    ["Codex", "codex -p ark-kimi"],
  ];
  ops.forEach((item, i) => {
    const y = 1.94 + i * 0.72;
    rect(slide, 0.9, y, 0.56, 0.44, i % 2 ? S.pale : S.dark, i % 2 ? S.pale : S.dark, 0);
    text(slide, String(i + 1), 1.06, y + 0.1, 0.24, 0.18, { size: 14, bold: true, color: i % 2 ? S.teal : S.white, align: "center", face: "Aptos" });
    text(slide, item[0], 1.72, y + 0.04, 1.55, 0.22, { size: 13, bold: true });
    text(slide, item[1], 3.2, y + 0.07, 3.6, 0.2, { size: 10.5, color: S.soft, face: "Menlo" });
  });
  rect(slide, 7.48, 1.94, 4.66, 3.62, S.white, S.muted, 1);
  text(slide, "排障优先级", 7.82, 2.2, 2.4, 0.26, { size: 16, bold: true });
  text(slide, "1. health 是否通\n2. 38443 是否是唯一入口\n3. 请求是否进入正确分支\n4. Authorization 是否由客户端提供\n5. tool call 是否完成 Responses 往返", 7.82, 2.78, 3.72, 1.9, {
    size: 12.2,
    color: S.soft,
  });
  footer(slide, 9, "Operational runbook");
}

function addSlide10() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "next");
  title(slide, "下一步：把成功状态固化成可重复安装。", 0.86, 31, 9.2);
  card(slide, 0.82, 2.0, 3.45, 1.18, "同步源码", "把远端合并后的 server.js 同步回材料仓库，避免文档和源码分叉。", S.teal, S.white);
  card(slide, 4.88, 2.0, 3.45, 1.18, "自动化验证", "补 health、Claude mapping、Codex profiles、tool call 四类 smoke test。", S.green, S.white);
  card(slide, 8.94, 2.0, 3.45, 1.18, "安装脚本化", "证书、LaunchAgent、Claude config、Codex config、回滚备份一次性处理。", S.gold, S.white);

  rect(slide, 0.82, 4.2, 11.58, 1.32, S.dark, S.dark, 0);
  text(slide, "分享边界", 1.18, 4.48, 1.8, 0.26, { size: 16, bold: true, color: S.white });
  text(slide, "材料不包含真实 API key、SSH 密码或私钥；公开日志前先检查 authorization、cookie 与个人路径。", 3.0, 4.5, 8.35, 0.34, {
    size: 14,
    color: "D7E6EC",
    bold: true,
  });
  footer(slide, 10, "Next actions and sharing boundary");
}

[
  addSlide01,
  addSlide02,
  addSlide03,
  addSlide04,
  addSlide05,
  addSlide06,
  addSlide07,
  addSlide08,
  addSlide09,
  addSlide10,
].forEach((fn) => fn());

fs.mkdirSync(path.dirname(OUT), { recursive: true });
pptx.writeFile({ fileName: OUT }).then(() => {
  console.log(OUT);
});
