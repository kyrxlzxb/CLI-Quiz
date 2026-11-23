const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const crypto = require('node:crypto');
const bank = require('./data/questions-dva.json');
const metadata = require('./data/import.json');
const original = require('../data/questions-dva.json');
function run(input) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dva-zh-test-'));
  try {
    for (const file of ['quiz.ps1', 'quiz.cmd', 'data/questions-dva.json', ...metadata.images]) {
      const dest = path.join(dir, file);
      fs.mkdirSync(path.dirname(dest), {recursive:true});
      fs.copyFileSync(path.join(__dirname, file), dest);
    }
    const exe = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
    const result = spawnSync(exe, ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(dir,'quiz.ps1')],
      {input,encoding:'utf8',timeout:60000,maxBuffer:16*1024*1024});
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    const logs = {};
    for (const file of ['mistakes-dva.jsonl','reviews-dva.jsonl']) {
      const p = path.join(dir,file);
      logs[file] = fs.existsSync(p) ? fs.readFileSync(p,'utf8').trim().split('\n').map(JSON.parse) : [];
    }
    return {output:result.stdout,logs};
  } finally {
    assert(path.resolve(dir).startsWith(path.resolve(os.tmpdir())+path.sep));
    assert(path.basename(dir).startsWith('dva-zh-test-'));
    fs.rmSync(dir,{recursive:true});
  }
}
test('all translations preserve original questions, English options and reviewed answers', () => {
  assert.equal(bank.length, 551);
  assert.equal(metadata.images.length, 22);
  bank.forEach((q,i) => {
    const {question_text,question_text_original,...rest} = q;
    assert.match(question_text, /[\u4e00-\u9fff]/);
    assert.deepEqual({...rest,question_text:question_text_original,explanation_en:original[i].explanation_en}, original[i]);
    assert.match(q.explanation_en, /[\u4e00-\u9fff]/);
    assert(q.explanation_en.startsWith(original[i].explanation_en.split('\n知识点：')[0].trim()));
    assert.equal((q.explanation_en.match(/知识点／记忆点：/g)||[]).length,1,q.qid);
    for (const option of q.options.filter(o => !o.is_correct)) {
      assert(q.explanation_en.includes(`\n\n${option.key}：`),`${q.qid}/${option.key}`);
    }
  });
  assert.equal(crypto.createHash('sha256').update(JSON.stringify(bank.map(({qid,explanation_en}) => ({qid,explanation_en})))).digest('hex'),metadata.explanations_sha256);
  assert.equal(fs.readFileSync(path.join(__dirname,'quiz.ps1')).subarray(0,3).toString('hex'),'efbbbf');
});
test('standalone folder runs all 551 questions, with self-reviews excluded from scoring', () => {
  const input = 'all\n'+bank.map(q=>q.special_data?.kind==='review' ? '\ny\n' : q.options.filter(o=>o.is_correct).map(o=>o.key).join(',')+'\n').join('');
  const {output,logs} = run(input);
  assert.match(output,/541\/541 正确/);
  assert.match(output,/自评 10 题/);
  assert.equal(logs['reviews-dva.jsonl'].length,10);
  assert.equal(logs['mistakes-dva.jsonl'].length,0);
  assert(output.includes(bank[0].question_text));
  assert(output.includes(bank[0].options[0].text));
  assert(!output.includes(bank[0].question_text_original));
  assert.match(output,/q0075-option-a.png/);
  assert.match(output,/image27.png/);
});
test('incorrect answer displays and saves Chinese explanation; correct answer does not', () => {
  const {output,logs} = run('409\nA,C\n');
  assert.match(output,/回答错误。正确答案：B, C/);
  assert(output.includes(bank[408].explanation_en));
  assert.match(output,/知识点／记忆点：/);
  assert.match(output,/其他选项为什么不选：/);
  assert.deepEqual(logs['mistakes-dva.jsonl'][0].correctAnswer,['B','C']);
  assert.equal(logs['mistakes-dva.jsonl'][0].explanation,bank[408].explanation_en);
  const correct = run('409\nB,C\n');
  assert.match(correct.output,/回答正确/);
  assert(!correct.output.includes(bank[408].explanation_en));
  assert.equal(correct.logs['mistakes-dva.jsonl'].length,0);
});
