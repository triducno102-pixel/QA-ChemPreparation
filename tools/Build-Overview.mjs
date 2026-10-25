// Sinh LabChem-TongQuan.html: một file HTML dễ đọc gồm phần tổng quan viết tay + toàn bộ docs/*.md.
// Chạy:  cd tools && npm install && node Build-Overview.mjs
// Nguồn:  tools/overview.partial.html (tổng quan), tools/overview.template.html (giao diện), docs/*.md, docs/img/*.png
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const read = p => fs.readFileSync(p, 'utf8');

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const strip = h => h.replace(/<[^>]+>/g, '');
const slug = t => strip(t).normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'muc';

// ---- phần tổng quan viết tay + nhúng ảnh
let overview = read(path.join(here, 'overview.partial.html'));
overview = overview.replace(/\{\{img:([\w-]+)\}\}/g, (_, name) => {
  const file = path.join(root, 'docs', 'img', name + '.png');
  return 'data:image/png;base64,' + fs.readFileSync(file).toString('base64');
});
const tocOverview = [...overview.matchAll(/<section id="([\w-]+)">\s*<h2><span class="num">(\d+)<\/span>([^<]+)<\/h2>/g)]
  .map(m => `<a href="#${m[1]}"><b>${m[2]}</b> ${m[3]}</a>`).join('\n    ');

// ---- các tài liệu md
const docsDir = path.join(root, 'docs');
const mdFiles = fs.readdirSync(docsDir).filter(f => /^\d\d-.*\.md$/.test(f)).sort();
const shortTitle = { '01': 'Thiết kế tổng thể', '02': 'Mô hình dữ liệu', '03': 'Power Automate (flow)', '04': 'Power Apps (màn hình, công thức)', '05': 'Bảo mật, rủi ro, kiểm thử', '06': 'Rà soát thiết kế' };

const details = [];
const tocDocs = [];
for (const f of mdFiles) {
  const no = f.slice(0, 2);
  let md = read(path.join(docsDir, f));
  const h1 = md.match(/^#\s+(.+)$/m);
  const title = shortTitle[no] || (h1 ? h1[1] : f);
  md = md.replace(/^#\s+.+\r?\n/, '');                      // bỏ H1: tiêu đề nằm ở <summary>

  let html = marked.parse(md, { gfm: true, breaks: false });
  // id cho heading (tiền tố theo tài liệu để không trùng)
  const used = new Set();
  html = html.replace(/<h([2-4])>([\s\S]*?)<\/h\1>/g, (m, lv, inner) => {
    let id = `d${no}-${slug(inner)}`; let n = 2; while (used.has(id)) id = `d${no}-${slug(inner)}-${n++}`; used.add(id);
    return `<h${lv} id="${id}">${inner}</h${lv}>`;
  });
  // mermaid
  html = html.replace(/<pre><code class="language-mermaid">([\s\S]*?)<\/code><\/pre>/g, '<pre class="mermaid">$1</pre>');
  // bảng cuộn ngang
  html = html.replace(/<table>/g, '<div class="tw"><table>').replace(/<\/table>/g, '</table></div>');
  // liên kết giữa các tài liệu và tới file nguồn
  html = html.replace(/href="(?:\.\/)?(\d\d)-[^"#]*\.md(?:#[^"]*)?"/g, 'href="#doc-$1"');
  html = html.replace(/href="\.\.\/([^"]+)"/g, 'href="$1"');
  html = html.replace(/<a href="(?!#|https?:|mailto:)/g, '<a href="');

  details.push(`<details class="doc" id="doc-${no}"><summary><span class="docno">${no}</span>${esc(title)}</summary><div class="md">${html}</div></details>`);
  tocDocs.push(`<a href="#doc-${no}"><b>${no}</b> ${esc(title)}</a>`);
}

const now = new Date();
const stamp = `${String(now.getDate()).padStart(2, '0')}/${String(now.getMonth() + 1).padStart(2, '0')}/${now.getFullYear()}`;
let out = read(path.join(here, 'overview.template.html'))
  .replace('{{BUILD_DATE}}', stamp)
  .replace('{{TOC_OVERVIEW}}', tocOverview)
  .replace('{{TOC_DOCS}}', tocDocs.join('\n    '))
  .replace('{{OVERVIEW}}', () => overview)
  .replace('{{DETAILS}}', () => details.join('\n'));

const target = path.join(root, 'LabChem-TongQuan.html');
fs.writeFileSync(target, out, 'utf8');
console.log(`written ${target} (${(out.length / 1024).toFixed(0)} KB), ${mdFiles.length} tài liệu, ${tocOverview.split('\n').length} mục tổng quan`);
