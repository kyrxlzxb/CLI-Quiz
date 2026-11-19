param([ValidateSet('default', 'dva')][string]$Bank = 'dva')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-QuizInput($prompt) {
    [Console]::Write($prompt)
    $line = [Console]::ReadLine()
    if ($null -eq $line) { return 'q' }
    return $line.Trim().ToLowerInvariant()
}

function Get-QuestionRange($inputText, $first, $last) {
    if ($inputText -eq 'all') { return $first, $last }
    if ($inputText -notmatch '^([0-9]+)(?:\s*-\s*([0-9]+))?$') { return }

    $start = 0
    if (-not [int]::TryParse($Matches[1], [ref]$start)) { return }
    $end = $start
    if ($Matches.ContainsKey(2) -and -not [int]::TryParse($Matches[2], [ref]$end)) { return }
    if ($start -ge $first -and $end -le $last -and $start -le $end) {
        return $start, $end
    }
}

function Get-SelectedAnswer($inputText, $keys, $count) {
    $choices = @($inputText.ToUpperInvariant() -split '\s*[,\uFF0C]\s*')
    $distinct = @($choices | Sort-Object -Unique)
    if ($choices.Count -ne $count -or $distinct.Count -ne $count) { return }
    foreach ($choice in $distinct) {
        if ($choice -notin $keys) { return }
    }
    return $distinct
}

function Get-QuizMedia($question, $root) {
    $items = @($question.media)
    foreach ($option in $question.options) { if ($option.media) { $items += $option.media } }
    foreach ($item in $items) {
        if (-not $item.src) { continue }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $root $item.src))
        $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetExtension($fullPath) -notin @('.png', '.jpg', '.jpeg', '.gif', '.webp')) {
            throw "Unsupported image path: $($item.src)"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing image: $fullPath" }
        $fullPath
    }
}

function Write-QuizRecord($path, $record) {
    $line = ConvertTo-Json -InputObject $record -Compress -Depth 8
    [IO.File]::AppendAllText($path, "$line`n", [System.Text.UTF8Encoding]::new($false))
}

try {
    $root = $PSScriptRoot
    $bankPath = Join-Path $root 'questions.json'
    $logPath = Join-Path $root 'mistakes.jsonl'
    if ($Bank -eq 'dva') {
        $bankPath = Join-Path $root 'data/questions-dva.json'
        $logPath = Join-Path $root 'mistakes-dva.jsonl'
    }
    $reviewLogPath = Join-Path $root 'reviews-dva.jsonl'
    $bankRecords = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($bankPath))
    $questions = @($bankRecords | Sort-Object qnum)
    if (-not $questions.Count) { throw 'The question bank is empty.' }
    $first = $questions[0].qnum
    $last = $questions[-1].qnum

    [Console]::WriteLine('DVA 中文刷题')
    if ($Bank -eq 'dva') { [Console]::WriteLine("AWS DVA-C02 - $($questions.Count) 题；中文题干，英文选项，答错后显示中文解析。") }
    [Console]::WriteLine('输入 q 退出；多选答案用英文逗号分隔，例如 B,C。')
    do {
        $inputText = Read-QuizInput "题目范围（$first-$last，如 20-40，或 all）："
        if ($inputText -eq 'q') { exit 0 }
        $range = @(Get-QuestionRange $inputText $first $last)
        if ($range.Count -ne 2) {
            [Console]::WriteLine('请输入有效题号或范围。')
            continue
        }

        $selected = @($questions | Where-Object { $_.qnum -ge $range[0] -and $_.qnum -le $range[1] })
        if (-not $selected.Count) { [Console]::WriteLine('No questions in that range.') }
    } until ($selected.Count)
    [Console]::WriteLine("`n$($selected.Count) 道题已选择。")

    $answered = 0
    $correct = 0
    $visited = 0
    $selfReviewed = 0
    $needsReview = 0
    foreach ($question in $selected) {
        $visited++
        $options = @($question.options | Sort-Object sort_order)
        $keys = @($options.key)
        $expected = @($options | Where-Object is_correct | ForEach-Object { $_.key } | Sort-Object)
        $expectedText = $expected -join ', '
        [Console]::WriteLine("`n第 $($question.qnum) 题（$visited/$($selected.Count)）")
        if ($question.audit_label) { [Console]::WriteLine("核查状态：$($question.audit_label)") }
        [Console]::WriteLine($question.question_text)
        foreach ($option in $options) {
            if ($option.text -or $option.media) { [Console]::WriteLine("$($option.key). $($option.text)") }
            if ($option.media) { [Console]::WriteLine("   Image: $($option.media.src)") }
        }
        $mediaPaths = @(Get-QuizMedia $question $root)
        if ($mediaPaths.Count) {
            [Console]::WriteLine('配图（答题时输入 i，用本地查看器打开）：')
            foreach ($imagePath in $mediaPaths) { [Console]::WriteLine("  $imagePath") }
        }

        if ($question.special_data.kind -eq 'review') {
            [Console]::WriteLine('信息不足：请按参考解析自评，不自动判分。')
            $inputText = Read-QuizInput '按回车显示参考解析，或输入 q 退出：'
            if ($inputText -eq 'q') { break }
            [Console]::WriteLine("中文解析：`n$($question.explanation_en)")
            do {
                $inputText = Read-QuizInput '自评：y 已理解，n 需要复习，q 退出：'
                if ($inputText -notin @('y', 'n', 'q')) { [Console]::WriteLine('请输入 y、n 或 q。') }
            } until ($inputText -in @('y', 'n', 'q'))
            if ($inputText -eq 'q') { break }
            $selfReviewed++
            if ($inputText -eq 'n') { $needsReview++ }
            Write-QuizRecord $reviewLogPath ([ordered]@{
                timestamp = [DateTime]::UtcNow.ToString('o'); bank = $Bank; qid = $question.qid
                questionNumber = $question.qnum; result = $(if ($inputText -eq 'y') { 'understood' } else { 'needs_review' })
                explanation = $question.explanation_en
            })
            continue
        }
        if (-not $expected.Count) { throw "Question $($question.qnum) has no verified answer and is not marked for self-review." }

        $prompt = '答案（一个字母）：'
        if ($expected.Count -gt 1) {
            $prompt = "答案（$($expected.Count) 个字母，用逗号分隔）："
        }
        do {
            $inputText = Read-QuizInput $prompt
            if ($inputText -eq 'q') { break }
            if ($inputText -eq 'i' -and $mediaPaths.Count) {
                foreach ($imagePath in $mediaPaths) { Invoke-Item -LiteralPath $imagePath }
                $answer = @()
                continue
            }
            $answer = @(Get-SelectedAnswer $inputText $keys $expected.Count)
            if (-not $answer.Count) {
                [Console]::WriteLine("请从 $($keys -join ', ') 中输入 $($expected.Count) 个不重复选项。")
            }
        } until ($answer.Count)
        if ($inputText -eq 'q') { break }

        $answered++
        if (($answer -join ', ') -eq $expectedText) {
            $correct++
            [Console]::WriteLine("回答正确。正确答案：$expectedText")
            # Correct answers advance without revealing the explanation.
            continue
        }

        [Console]::WriteLine("回答错误。正确答案：$expectedText")
        $explanation = $question.explanation_en
        if (-not $explanation) { $explanation = 'No explanation available.' }
        [Console]::WriteLine("中文解析：`n$explanation")
        $mistake = [ordered]@{
            timestamp = [DateTime]::UtcNow.ToString('o')
            qid = $question.qid
            questionNumber = $question.qnum
            answer = $answer
            correctAnswer = $expected
            explanation = $explanation
        }
        Write-QuizRecord $logPath $mistake
    }
    [Console]::WriteLine("`n练习结束。自动判分：$correct/$answered 正确。")
    if ($answered -gt $correct) { [Console]::WriteLine("错题已保存到 $([IO.Path]::GetFileName($logPath)).") }
    if ($selfReviewed) { [Console]::WriteLine("自评 $selfReviewed 题，需复习 $needsReview 题。已保存到 reviews-dva.jsonl，不计入自动得分。") }
} catch {
    [Console]::Error.WriteLine("Quiz error: $($_.Exception.Message)")
    exit 1
}
