// 指南正文的行内 markdown 子集解析（官网 feed.ts 只产出这几种）：
//   **粗体**  *斜体*  `代码`  [文字](链接)  以及反斜杠转义 \* \_ \[ \] \` \\
// 解析成扁平片段，由页面用 Text + Span 渲染（链接片段点按外开浏览器）。

export interface InlineSegment {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  link: string;   // '' = 非链接
}

function seg(text: string, bold: boolean, italic: boolean, code: boolean, link: string): InlineSegment {
  return { text: text, bold: bold, italic: italic, code: code, link: link };
}

/// 去掉链接文字里残留的强调标记与转义（链接内不再细分样式）
function stripMarks(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const c = text.charAt(i);
    if (c === '\\' && i + 1 < text.length) {
      out += text.charAt(i + 1);
      i++;
      continue;
    }
    if (c === '*' || c === '`') {
      continue;
    }
    out += c;
  }
  return out;
}

export function parseInline(md: string): InlineSegment[] {
  const out: InlineSegment[] = [];
  let buf = '';
  let bold = false;
  let italic = false;

  const flush = () => {
    if (buf !== '') {
      out.push(seg(buf, bold, italic, false, ''));
      buf = '';
    }
  };

  let i = 0;
  while (i < md.length) {
    const c = md.charAt(i);
    // 转义
    if (c === '\\' && i + 1 < md.length) {
      buf += md.charAt(i + 1);
      i += 2;
      continue;
    }
    // 行内代码：到下一个反引号为止，内部不解析
    if (c === '`') {
      const end = md.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out.push(seg(md.substring(i + 1, end), false, false, true, ''));
        i = end + 1;
        continue;
      }
    }
    // 链接 [text](url)
    if (c === '[') {
      const close = md.indexOf('](', i + 1);
      const paren = close > i ? md.indexOf(')', close + 2) : -1;
      if (close > i && paren > close) {
        flush();
        const label = stripMarks(md.substring(i + 1, close));
        const url = md.substring(close + 2, paren).trim();
        out.push(seg(label, bold, italic, false, url));
        i = paren + 1;
        continue;
      }
    }
    // 粗体 / 斜体开关
    if (c === '*') {
      if (md.charAt(i + 1) === '*') {
        flush();
        bold = !bold;
        i += 2;
        continue;
      }
      flush();
      italic = !italic;
      i += 1;
      continue;
    }
    buf += c;
    i++;
  }
  flush();
  return out;
}

/// 纯文本（去掉全部标记），用于无法承载样式的地方
export function plainInline(md: string): string {
  return parseInline(md).map((s: InlineSegment) => s.text).join('');
}
