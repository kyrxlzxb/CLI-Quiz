// Rebuild this standalone edition: node dva-zh/build.cjs <reviewed PWA checkout>
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = __dirname;
assert(process.argv[2], 'Provide the reviewed PWA checkout path.');
const source = path.resolve(process.argv[2]);
const read = file => fs.readFileSync(path.join(source, file), 'utf8').replace(/^\uFEFF/, '');
const bank = JSON.parse(read('data/questions-dva.json'));
const zh = JSON.parse(read('data/dva-stems-zh.json'));
const fingerprint = JSON.parse(read('data/dva-stems-zh-source.json'));
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
assert.equal(hash(JSON.stringify(bank.map(({qid,question_text}) => ({qid,question_text})))), fingerprint.sha256);
assert.equal(bank.length, 551);
assert.deepEqual(Object.keys(zh).sort(), bank.map(q => q.qid).sort());
const images = new Set();
const output = bank.map(q => {
  assert(/[\u4e00-\u9fff]/.test(zh[q.qid]), q.qid);
  assert(/[\u4e00-\u9fff]/.test(q.explanation_en), `Missing Chinese explanation: ${q.qid}`);
  for (const media of [...(q.media || []), ...q.options.map(o => o.media).filter(Boolean)]) {
    assert(/^assets\/dva(?:-supplement)?\/[\w.-]+\.(png|jpg|jpeg)$/.test(media.src));
    images.add(media.src);
  }
  return {...q, question_text_original: q.question_text, question_text: zh[q.qid]};
});
fs.mkdirSync(path.join(root, 'data'), {recursive:true});
fs.writeFileSync(path.join(root, 'data/questions-dva.json'), JSON.stringify(output, null, 2)+'\n');
for (const file of images) {
  fs.mkdirSync(path.dirname(path.join(root, file)), {recursive:true});
  fs.copyFileSync(path.join(source, file), path.join(root, file));
}
let script = fs.readFileSync(path.join(root, '../quiz.ps1'), 'utf8').replace(/^\uFEFF/, '');
function replace(from, to) {
  assert(script.includes(from), `Runner template changed: ${from}`);
  script = script.split(from).join(to);
}
replace("[string]$Bank = 'default'", "[string]$Bank = 'dva'");
replace('CLI Quiz', 'DVA 中文刷题');
replace('records. English questions; reviewed explanations retained.', '题；中文题干，英文选项，答错后显示中文解析。');
replace('Enter q at any prompt to quit.', '输入 q 退出；多选答案用英文逗号分隔，例如 B,C。');
replace('Question range ($first-$last, e.g. 20-40, or all): ', '题目范围（$first-$last，如 20-40，或 all）：');
replace('Enter a valid question number or an inclusive range.', '请输入有效题号或范围。');
replace('question(s) selected.', '道题已选择。');
replace('Question $($question.qnum) ($visited/$($selected.Count))', '第 $($question.qnum) 题（$visited/$($selected.Count)）');
replace('Review status: ', '核查状态：');
replace('Images (enter i at the answer prompt to open locally):', '配图（答题时输入 i，用本地查看器打开）：');
replace('Insufficient information: self-review only, excluded from automatic scoring.', '信息不足：请按参考解析自评，不自动判分。');
replace('Press Enter to show the review, or q to quit: ', '按回车显示参考解析，或输入 q 退出：');
replace('Explanation:', '中文解析：');
replace('Self-review: y = understood, n = needs review, q = quit: ', '自评：y 已理解，n 需要复习，q 退出：');
replace('Enter y, n, or q.', '请输入 y、n 或 q。');
replace('Answer (one letter): ', '答案（一个字母）：');
replace('Answer ($($expected.Count) letters, separated by commas): ', '答案（$($expected.Count) 个字母，用逗号分隔）：');
replace('Enter $($expected.Count) distinct choice(s) from $($keys -join \', \').', '请从 $($keys -join \', \') 中输入 $($expected.Count) 个不重复选项。');
replace('Correct. Correct answer: ', '回答正确。正确答案：');
replace('Incorrect. Correct answer: ', '回答错误。正确答案：');
replace('            if ($Bank -eq \'dva\' -and $question.explanation_en) { [Console]::WriteLine("中文解析：`n$($question.explanation_en)") }', '            # Correct answers advance without revealing the explanation.');
replace('Session complete. $correct/$answered correct.', '练习结束。自动判分：$correct/$answered 正确。');
replace('Mistakes saved to ', '错题已保存到 ');
replace('Self-reviewed: $selfReviewed; needs review: $needsReview. Saved to reviews-dva.jsonl (not included in score).', '自评 $selfReviewed 题，需复习 $needsReview 题。已保存到 reviews-dva.jsonl，不计入自动得分。');
// Windows PowerShell 5.1 needs a BOM to parse Chinese string literals correctly.
fs.writeFileSync(path.join(root, 'quiz.ps1'), '\uFEFF'+script);
fs.writeFileSync(path.join(root, 'data/import.json'), JSON.stringify({
  source:'kyrxlzxb/aws-quiz-pwa-offline', source_commit:'f39f654', records:output.length,
  language:'Chinese stems, original English choices, Chinese explanations on incorrect answers',
  source_stems_sha256:fingerprint.sha256, images:[...images].sort(),
}, null, 2)+'\n');
console.log(`Built standalone Chinese CLI: ${output.length} records, ${images.size} images.`);
