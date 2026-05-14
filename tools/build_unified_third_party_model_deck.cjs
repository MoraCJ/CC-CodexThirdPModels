#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const PptxGenJS = require("/Users/chjia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pptxgenjs");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "docs", "unified-proxy-third-party-models-intro.pptx");

const pptx = new PptxGenJS();
pptx.defineLayout({ name: "CJ_WIDE", width: 13.333, height: 7.5 });
pptx.layout = "CJ_WIDE";
pptx.author = "CJ / Codex";
pptx.company = "CJ";
pptx.subject = "Configure Claude Code and Codex for third-party models through a unified local proxy";
pptx.title = "通过统一代理配置 Claude Code 与 Codex 第三方模型";
pptx.lang = "zh-CN";
pptx.theme = {
  headFontFace: "Aptos Display",
  bodyFontFace: "PingFang SC",
  lang: "zh-CN",
};

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
    fit: "shrink",
    paraSpaceAfterPt: opts.after ?? 0,
    breakLineOnHyphen: false,
  });
}

function rule(slide, x, y, w, color = S.muted, h = 0.012) {
  rect(slide, x, y, w, h, color, color, 0);
}

function kicker(slide, label) {
  rect(slide, 0.58, 0.48, 0.1, 0.1, S.teal);
  text(slide, label.toUpperCase().split("").join(" "), 0.82, 0.43, 5.7, 0.24, {
    size: 8.5,
    color: S.soft,
    bold: true,
    face: "Aptos",
  });
}

function title(slide, value, y = 0.86, size = 31, w = 9.2) {
  text(slide, value, 0.58, y, w, 0.72, {
    size,
    bold: true,
    color: S.ink,
    face: "Aptos Display",
  });
}

function subtitle(slide, value, x, y, w, h, size = 13) {
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

function card(slide, x, y, w, h, head, body, accent = S.teal, fill = S.white) {
  rect(slide, x, y, w, h, fill, S.muted, 1);
  rect(slide, x, y, 0.05, h, accent, accent, 0);
  text(slide, head, x + 0.22, y + 0.18, w - 0.4, 0.28, { size: 13.6, bold: true });
  text(slide, body, x + 0.22, y + 0.58, w - 0.42, h - 0.7, { size: 10.2, color: S.soft });
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
  rect(slide, x1, y, Math.max(0.2, x2 - x1 - 0.18), 0.025, color, color, 0);
  text(slide, ">", x2 - 0.18, y - 0.12, 0.2, 0.26, {
    size: 16,
    color,
    bold: true,
    align: "center",
    face: "Aptos",
  });
}

function table(slide, x, y, widths, rowH, rows, headerFill = S.pale) {
  rows.forEach((row, r) => {
    let xx = x;
    row.forEach((cell, c) => {
      const fill = r === 0 ? headerFill : r % 2 ? S.white : "F2F7F9";
      rect(slide, xx, y + r * rowH, widths[c], rowH, fill, S.muted, 0.7);
      text(slide, cell, xx + 0.08, y + r * rowH + 0.08, widths[c] - 0.16, rowH - 0.14, {
        size: r === 0 ? 8.5 : 7.9,
        bold: r === 0,
        color: r === 0 ? S.ink : S.soft,
        valign: "mid",
      });
      xx += widths[c];
    });
  });
}

function slide01() {
  const slide = pptx.addSlide();
  bg(slide);
  rect(slide, 0.58, 0.54, 0.07, 0.72, S.teal);
  text(slide, "Unified Local Proxy", 0.82, 0.56, 4.2, 0.24, { size: 12, color: S.soft, bold: true, face: "Aptos" });
  text(slide, "通过统一代理配置\nClaude Code 与 Codex\n使用第三方模型", 0.58, 1.45, 7.4, 2.0, {
    size: 36,
    bold: true,
    color: S.ink,
    face: "Aptos Display",
  });
  subtitle(slide, "一个本机 HTTPS 入口，统一处理 Claude 槽位映射、Codex Responses API 桥接、证书信任与运行验证。", 0.6, 3.74, 7.15, 0.48, 14);
  rect(slide, 8.74, 0, 4.6, 7.5, S.dark);
  text(slide, "目标状态", 9.26, 0.88, 2.1, 0.28, { size: 13, color: "A7CBD6", bold: true });
  text(slide, "Claude Code\nCodex\n统一接入 Ark\n第三方模型", 9.26, 1.46, 3.0, 1.9, {
    size: 27,
    bold: true,
    color: S.white,
    face: "Aptos Display",
  });
  rule(slide, 9.26, 3.8, 2.7, "315363");
  text(slide, "2026-05-14\n标准方案介绍版", 9.26, 4.1, 2.3, 0.55, { size: 12, color: "C7D8DF" });
  footer(slide, 1, "Unified third-party model configuration");
}

function slide02() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "advantages");
  title(slide, "统一代理带来的四个优势。");
  subtitle(slide, "方案核心不是工具各自配置，而是把入口、证书、模型策略、验证口径收敛到同一个本机 HTTPS 层。", 0.6, 1.72, 9.5, 0.35);
  card(slide, 0.82, 2.18, 2.82, 1.32, "统一入口", "Claude Code 与 Codex 都指向 https://127.0.0.1:38443。", S.teal, S.white);
  card(slide, 3.9, 2.18, 2.82, 1.32, "统一证书", "本地 CA、Keychain 信任、host loop 证书环境统一处理。", S.green, S.white);
  card(slide, 6.98, 2.18, 2.82, 1.32, "统一策略", "Claude 保留槽位映射，Codex 直接使用真实模型名。", S.gold, S.sand);
  card(slide, 10.06, 2.18, 2.82, 1.32, "统一验收", "health、代理日志、profiles、tool call 用同一套信号验证。", S.blue, "EEF4FF");
  tag(slide, "标准能力：一个代理完成协议适配、模型路由、证书信任和运行验证", 2.04, 5.25, 9.25, S.dark);
  footer(slide, 2, "Unified proxy advantages");
}

function slide03() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "architecture");
  title(slide, "目标架构：一个 38443 入口，两条协议分支。", 0.86, 31, 9.8);
  rect(slide, 5.05, 2.75, 3.2, 1.1, S.dark, S.dark, 0);
  text(slide, "claude-local-proxy/server.js", 5.3, 3.06, 2.65, 0.28, { size: 14.5, bold: true, color: S.white });
  tag(slide, "https://127.0.0.1:38443", 5.25, 4.1, 2.75, S.pale, S.teal);
  card(slide, 0.8, 1.9, 3.28, 1.0, "Claude Code", "/v1/messages\n/v1/messages/count_tokens", S.teal, S.white);
  card(slide, 0.8, 4.25, 3.28, 0.88, "Codex", "/v1/responses", S.gold, S.white);
  card(slide, 9.05, 1.9, 3.3, 1.0, "Ark coding", "/api/coding\nAnthropic-compatible", S.teal, S.white);
  card(slide, 9.05, 4.25, 3.3, 0.88, "Ark coding v3", "/chat/completions\nOpenAI-compatible", S.gold, S.white);
  arrow(slide, 4.1, 2.45, 4.86, S.teal);
  arrow(slide, 8.32, 2.45, 8.96, S.teal);
  arrow(slide, 4.1, 4.7, 4.86, S.gold);
  arrow(slide, 8.32, 4.7, 8.96, S.gold);
  text(slide, "Claude：透传 + 槽位映射", 5.06, 1.98, 2.8, 0.22, { size: 11.5, color: S.soft });
  text(slide, "Codex：Responses -> Chat -> Responses", 4.74, 5.16, 3.4, 0.22, { size: 11.5, color: S.soft });
  footer(slide, 3, "Target architecture");
}

function slide04() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "https");
  title(slide, "本机 HTTPS 和证书信任是成败关键。", 0.86, 31, 9.6);
  card(slide, 0.78, 2.0, 3.7, 1.08, "证书生成", "本地 CA + server certificate；SAN 包含 127.0.0.1、localhost、::1。", S.teal, S.white);
  card(slide, 4.82, 2.0, 3.7, 1.08, "Keychain 信任", "Desktop/Electron 不等同于 shell，不能只依赖 curl --cacert。", S.green, S.white);
  card(slide, 8.86, 2.0, 3.7, 1.08, "Cowork 兜底", "host loop 环境不完整时，用 launcher 注入 NODE_EXTRA_CA_CERTS。", S.gold, S.white);
  rect(slide, 1.18, 4.2, 10.95, 1.2, S.dark, S.dark, 0);
  text(slide, "判断原则", 1.58, 4.52, 1.3, 0.26, { size: 15, bold: true, color: S.white });
  text(slide, "普通 curl https://127.0.0.1:38443/health 能成功，是系统信任链足够的关键证据。", 2.96, 4.54, 8.2, 0.3, {
    size: 14,
    bold: true,
    color: "D7E6EC",
  });
  footer(slide, 4, "Local HTTPS and trust chain");
}

function slide05() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "proxy");
  title(slide, "统一代理需要实现四个能力。", 0.86, 31, 8.7);
  const items = [
    ["1", "健康检查", "/health 返回 upstream、codexUpstream、模型映射"],
    ["2", "Claude 透传", "转发 Anthropic-compatible 请求，透传认证头"],
    ["3", "模型映射", "opus/sonnet/haiku -> glm/kimi/doubao"],
    ["4", "Codex 桥接", "Responses API -> Chat Completions -> Responses API"],
  ];
  items.forEach((item, i) => {
    const x = 0.75 + i * 3.05;
    rect(slide, x, 2.32, 2.55, 2.05, i === 3 ? S.sand : S.white, S.muted, 1);
    text(slide, item[0], x + 0.18, 2.62, 0.35, 0.35, { size: 18, bold: true, color: i === 3 ? S.gold : S.teal, face: "Aptos" });
    text(slide, item[1], x + 0.58, 2.66, 1.45, 0.24, { size: 14.5, bold: true });
    text(slide, item[2], x + 0.18, 3.26, 2.06, 0.56, { size: 10, color: S.soft });
  });
  tag(slide, "API key 不写死在代理代码中，由客户端配置或环境变量提供", 2.48, 5.45, 8.38, S.dark);
  footer(slide, 5, "Proxy capability checklist");
}

function slide06() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "models");
  title(slide, "模型策略：Claude 映射，Codex 真实模型名。", 0.86, 31, 9.4);
  table(slide, 0.62, 1.86, [2.0, 3.0, 2.55, 1.45, 2.25], 0.53, [
    ["工具/配置", "客户端模型名", "实际上游模型", "策略", "用途"],
    ["Claude", "claude-opus-4-6", "glm-5.1", "代理映射", "复杂推理"],
    ["Claude", "claude-sonnet-4-6", "kimi-k2.6", "代理映射", "默认主力"],
    ["Claude", "claude-haiku-4-5", "doubao-seed-2.0-pro", "代理映射", "快速任务"],
    ["Codex ark-doubao", "doubao-seed-2.0-pro", "doubao-seed-2.0-pro", "真实模型", "默认/快速"],
    ["Codex ark-kimi", "kimi-k2.6", "kimi-k2.6", "真实模型", "复杂编码"],
    ["Codex ark-glm", "glm-5.1", "glm-5.1", "真实模型", "高质量推理"],
  ]);
  footer(slide, 6, "Model naming strategy");
}

function slide07() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "claude");
  title(slide, "Claude Code 配置重点：保留槽位名。", 0.86, 31, 9.2);
  rect(slide, 0.78, 1.92, 5.55, 3.6, S.dark, S.dark, 0);
  text(slide, `"ANTHROPIC_BASE_URL": "https://127.0.0.1:38443"\n"ANTHROPIC_AUTH_TOKEN": "<ARK_API_KEY>"\n"ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6"\n"ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6"\n"ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5"\n"NODE_EXTRA_CA_CERTS": "<PROJECT_ROOT>/certs/ca.crt"`, 1.08, 2.22, 4.95, 2.55, {
    size: 10.7,
    color: S.white,
    face: "Menlo",
  });
  card(slide, 7.0, 2.0, 4.55, 0.86, "Desktop 3P Gateway", "gatewayBaseUrl 指向 38443；inferenceModels 写 Claude 槽位。", S.teal, S.white);
  card(slide, 7.0, 3.08, 4.55, 0.86, "CLI / host settings", "删除 ANTHROPIC_MODEL 和 modelOverrides，避免双重映射。", S.green, S.white);
  card(slide, 7.0, 4.16, 4.55, 0.86, "Cowork", "证书失败时用 launcher 注入 CA 环境。", S.gold, S.white);
  footer(slide, 7, "Claude Code configuration");
}

function slide08() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "codex");
  title(slide, "Codex 配置重点：provider + profiles。", 0.86, 31, 8.8);
  rect(slide, 0.78, 1.9, 6.25, 3.7, S.dark, S.dark, 0);
  text(slide, `model_provider = "ark-coding"\nmodel = "doubao-seed-2.0-pro"\n\n[model_providers.ark-coding]\nwire_api = "responses"\nbase_url = "https://127.0.0.1:38443/v1"\nrequires_openai_auth = true\n\n[profiles.ark-kimi]\nmodel = "kimi-k2.6"`, 1.08, 2.22, 5.65, 2.8, {
    size: 11.2,
    color: S.white,
    face: "Menlo",
  });
  card(slide, 7.72, 2.05, 4.18, 0.86, "默认", "doubao-seed-2.0-pro，medium reasoning", S.gold, S.white);
  card(slide, 7.72, 3.18, 4.18, 0.86, "编码", "ark-kimi -> kimi-k2.6，high reasoning", S.green, S.white);
  card(slide, 7.72, 4.31, 4.18, 0.86, "推理", "ark-glm -> glm-5.1，high reasoning", S.teal, S.white);
  tag(slide, "运行：codex -p ark-doubao / ark-kimi / ark-glm", 2.08, 6.16, 8.95, S.pale, S.teal);
  footer(slide, 8, "Codex provider profiles");
}

function slide09() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "codex app");
  title(slide, "Codex App 切模型：默认配置或启动覆盖。", 0.86, 30, 10.2);
  subtitle(slide, "CLI 支持 -p profile；App 启动入口更适合用 ~/.codex/config.toml 顶层默认值或 codex app -c 覆盖。", 0.6, 1.68, 9.6, 0.35);
  card(slide, 0.82, 2.18, 3.45, 1.08, "CLI 临时切换", "codex -p ark-kimi\ncodex -p ark-glm", S.teal, S.white);
  card(slide, 4.88, 2.18, 3.45, 1.08, "App 默认切换", "修改 ~/.codex/config.toml 顶层 model，重启 App 或新开会话。", S.green, S.white);
  card(slide, 8.94, 2.18, 3.45, 1.08, "App 启动覆盖", "codex app /path -c 'model=\"kimi-k2.6\"' ...", S.gold, S.sand);
  rect(slide, 1.0, 4.08, 11.25, 1.36, S.dark, S.dark, 0);
  text(slide, `codex app /path/to/project \\\n  -c 'model_provider="ark-coding"' \\\n  -c 'model="kimi-k2.6"' \\\n  -c 'model_reasoning_effort="high"'`, 1.34, 4.34, 7.6, 0.74, {
    size: 11.2,
    color: S.white,
    face: "Menlo",
  });
  text(slide, "验证信号", 9.25, 4.32, 1.2, 0.24, { size: 13, bold: true, color: "D7E6EC" });
  text(slide, "代理日志出现\ncodex responses model\nkimi-k2.6 -> kimi-k2.6", 9.25, 4.74, 2.05, 0.46, {
    size: 9.8,
    color: "D7E6EC",
  });
  tag(slide, "当前已打开会话不保证热切换；稳定验证请重启 App 或新开 workspace", 2.28, 6.12, 8.8, S.pale, S.teal);
  footer(slide, 9, "Codex App model switching");
}

function slide10() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "validation");
  title(slide, "验收矩阵：不要只看 UI，要看行为信号。", 0.86, 31, 9.8);
  table(slide, 0.72, 1.8, [2.2, 6.85, 1.35], 0.56, [
    ["检查项", "成功信号", "状态"],
    ["端口", "38443 LISTEN；旧 38444 不监听", "OK"],
    ["健康检查", "/health 返回 ok、upstream、codexUpstream、模型字段", "OK"],
    ["Claude Desktop", "ConfigHealth recomputed { state: 'healthy', provider: 'gateway' }", "OK"],
    ["Claude 请求", "POST /v1/messages -> 200；映射日志可见", "OK"],
    ["Codex profiles", "ark-doubao / ark-kimi / ark-glm 均可回复", "OK"],
    ["Tool call", "function_call 与 function_call_output 闭环正常", "OK"],
  ]);
  footer(slide, 10, "Validation matrix");
}

function slide11() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "operations");
  title(slide, "运维流程：进程、端口、日志、配置、回滚。", 0.86, 31, 9.7);
  const ops = [
    ["进程", "launchctl print / kickstart"],
    ["端口", "lsof -nP -iTCP:38443"],
    ["健康", "curl -sk https://127.0.0.1:38443/health"],
    ["日志", "proxy.log / proxy.err.log / Claude main.log"],
    ["回滚", "恢复 server.js 与配置备份"],
  ];
  ops.forEach((item, i) => {
    const y = 1.88 + i * 0.72;
    rect(slide, 0.9, y, 0.56, 0.44, i % 2 ? S.pale : S.dark, i % 2 ? S.pale : S.dark, 0);
    text(slide, String(i + 1), 1.06, y + 0.1, 0.24, 0.18, { size: 14, bold: true, color: i % 2 ? S.teal : S.white, align: "center", face: "Aptos" });
    text(slide, item[0], 1.72, y + 0.04, 1.5, 0.22, { size: 13, bold: true });
    text(slide, item[1], 3.05, y + 0.07, 4.55, 0.2, { size: 10.3, color: S.soft, face: "Menlo" });
  });
  rect(slide, 8.0, 1.88, 3.9, 3.5, S.white, S.muted, 1);
  text(slide, "故障优先级", 8.34, 2.16, 1.8, 0.26, { size: 16, bold: true });
  text(slide, "1. health 是否通\n2. 证书是否被系统信任\n3. 请求是否进入正确分支\n4. Authorization 是否存在\n5. tool call 转换是否完整", 8.34, 2.72, 3.0, 1.75, {
    size: 11.8,
    color: S.soft,
  });
  footer(slide, 11, "Operations and troubleshooting");
}

function slide12() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "security");
  title(slide, "安全边界：材料可分享，密钥不进材料。", 0.86, 31, 9.2);
  card(slide, 0.82, 2.0, 3.42, 1.12, "密钥", "真实 API key 只进入本机配置或环境变量，文档统一使用占位符。", S.red, "FCEEEE");
  card(slide, 4.86, 2.0, 3.42, 1.12, "证书", "certs/*.key 不公开、不入库；迁移机器优先重新生成。", S.gold, S.sand);
  card(slide, 8.9, 2.0, 3.42, 1.12, "日志", "公开前扫描 authorization、x-api-key、cookie、个人路径。", S.teal, S.white);
  rect(slide, 1.16, 4.4, 10.95, 1.1, S.dark, S.dark, 0);
  text(slide, "公司批量部署建议", 1.55, 4.74, 2.2, 0.24, { size: 15, bold: true, color: S.white });
  text(slide, "CA 信任通过 MDM/配置描述文件下发；安装脚本只负责代理、LaunchAgent、工具配置和 smoke test。", 3.75, 4.75, 7.3, 0.3, {
    size: 13.5,
    bold: true,
    color: "D7E6EC",
  });
  footer(slide, 12, "Security and sharing boundary");
}

function slide13() {
  const slide = pptx.addSlide();
  bg(slide);
  kicker(slide, "standardization");
  title(slide, "标准化交付：一份 PPT、一份技术手册、一份 AI runbook。", 0.86, 30, 10.5);
  card(slide, 0.82, 2.08, 3.55, 1.16, "介绍 PPT", "说明统一代理优势、架构如何工作、Claude/Codex 如何分别配置。", S.teal, S.white);
  card(slide, 4.9, 2.08, 3.55, 1.16, "技术手册 Word", "面向人类维护者，覆盖部署、配置、验证、运维、回滚、安全。", S.green, S.white);
  card(slide, 8.98, 2.08, 3.55, 1.16, "AI Runbook", "面向其他 AI 工具，使用占位符、步骤、检查点和输出格式。", S.gold, S.sand);
  tag(slide, "下一步：把远端已验证的合并版 server.js 同步回材料仓库，并补自动 smoke test", 1.68, 5.26, 10.0, S.dark);
  footer(slide, 13, "Deliverables and next standardization step");
}

[
  slide01,
  slide02,
  slide03,
  slide04,
  slide05,
  slide06,
  slide07,
  slide08,
  slide09,
  slide10,
  slide11,
  slide12,
  slide13,
].forEach((fn) => fn());

fs.mkdirSync(path.dirname(OUT), { recursive: true });
pptx.writeFile({ fileName: OUT }).then(() => console.log(OUT));
