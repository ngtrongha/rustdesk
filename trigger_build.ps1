param(
    [string]$TagName = "v1.5.12"
)

$rootDir = $PSScriptRoot
$cred = cmd.exe /c "echo url=https://github.com/ngtrongha/rustdesk.git | git -C `"$rootDir`" credential fill" 2>$null | Out-String
$match = [regex]::Match($cred, 'password=(.+)')
if (-not $match.Success) {
    Write-Error "Khong the lay GitHub token tu git credential helper."
    exit 1
}
$token = $match.Groups[1].Value.Trim()
$headers = @{
    'Authorization' = "Bearer $token"
    'Accept' = 'application/vnd.github.v3+json'
    'User-Agent' = 'Antigravity'
}

$branches = @('feat/upgrade-flutter-win10', 'win7-lts')
foreach ($branch in $branches) {
    $body = @{
        'ref' = $branch
        'inputs' = @{ 'tag_name' = $TagName }
    } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri 'https://api.github.com/repos/ngtrongha/rustdesk/actions/workflows/flutter-tag.yml/dispatches' -Method Post -Headers $headers -Body $body
        Write-Host "[SUCCESS] Da kich hoat build GitHub Actions cho nhanh: $branch" -ForegroundColor Green
    } catch {
        Write-Error "[ERROR] Loi khi goi build cho $branch : $_"
    }
    Start-Sleep -Seconds 1
}
