const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const bank = JSON.parse(fs.readFileSync(path.join(root, 'data/questions-dva.json'), 'utf8'));
const metadata = JSON.parse(fs.readFileSync(path.join(root, 'data/dva-import.json'), 'utf8'));
const powershell = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');

function run(input, bankName = 'dva') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dva-cli-test-'));
  try {
    for (const file of ['quiz.ps1', 'questions.json', 'data/questions-dva.json', ...metadata.images]) {
      const dest = path.join(dir, file);
      fs.mkdirSync(path.dirname(dest), {recursive:true});
      fs.copyFileSync(path.join(root, file), dest);
    }
    const result = spawnSync(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(dir, 'quiz.ps1'), '-Bank', bankName], {
      input, encoding:'utf8', timeout: 60000, maxBuffer: 16 * 1024 * 1024,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    const logs = {};
    for (const file of ['mistakes.jsonl','mistakes-dva.jsonl','reviews-dva.jsonl']) {
      const p = path.join(dir, file);
      logs[file] = fs.existsSync(p) ? fs.readFileSync(p,'utf8').trim().split('\n').map(JSON.parse) : [];
    }
    return {output:result.stdout, logs};
  } finally {
    const resolved = path.resolve(dir);
    assert(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert(path.basename(resolved).startsWith('dva-cli-test-'));
    fs.rmSync(resolved, {recursive:true});
  }
}

test('all 551 records retain the reviewed source checksum and 22 offline images', () => {
  assert.equal(bank.length, 551);
  const bytes = fs.readFileSync(path.join(root, 'data/questions-dva.json'));
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), metadata.sha256);
  assert.equal(metadata.images.length, 22);
  for (const image of metadata.images) assert(fs.statSync(path.join(root,image)).size > 0);
});

test('complete DVA run grades 541 questions and keeps 10 self-reviews separate', () => {
  const input = 'all\n' + bank.map(q => q.special_data?.kind === 'review'
    ? '\ny\n' : q.options.filter(o => o.is_correct).map(o=>o.key).join(',')+'\n').join('');
  const {output, logs} = run(input);
  assert.match(output, /551 record/);
  assert.match(output, /541\/541 correct/);
  assert.match(output, /Self-reviewed: 10/);
  assert.equal(logs['reviews-dva.jsonl'].length, 10);
  assert.equal(logs['mistakes-dva.jsonl'].length, 0);
  assert.match(output, /q0075-option-a.png/);
  assert.match(output, /image27.png/);
});

test('old wrong multi-answer is rejected, then saved with the corrected BC answer', () => {
  const {output, logs} = run('409\nB\nA,C\n');
  assert.match(output, /Enter 2 distinct choice/);
  assert.match(output, /Incorrect. Correct answer: B, C/);
  assert.deepEqual(logs['mistakes-dva.jsonl'][0].correctAnswer, ['B','C']);
  assert.equal(logs['mistakes.jsonl'].length, 0);
});

test('self-review n is never counted as an automatically incorrect answer', () => {
  const {output, logs} = run('442\n\nn\n');
  assert.match(output, /0\/0 correct/);
  assert.match(output, /needs review: 1/);
  assert.equal(logs['reviews-dva.jsonl'][0].result, 'needs_review');
  assert.equal(logs['mistakes-dva.jsonl'].length, 0);
});

test('invalid range and quitting a self-review do not create results', () => {
  const {output, logs} = run('552\n442\nq\n');
  assert.match(output, /Enter a valid question/);
  assert.equal(logs['reviews-dva.jsonl'].length, 0);
});

test('default bank still loads and scores using the original entry point', () => {
  const q = JSON.parse(fs.readFileSync(path.join(root,'questions.json'),'utf8').replace(/^\uFEFF/,'')).sort((a,b)=>a.qnum-b.qnum)[0];
  const answer = q.options.filter(o=>o.is_correct).map(o=>o.key).join(',');
  const {output} = run(`${q.qnum}\n${answer}\n`, 'default');
  assert.match(output, /1\/1 correct/);
  assert.doesNotMatch(output, /AWS DVA-C02/);
});
