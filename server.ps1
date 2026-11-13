# ==============================================================================
# HE THONG AI AGENT THAM DINH DOI TAC PHAN PHOI - CONG TY GIA DUNG DAI THANH
# Localhost Web & API Server (TcpListener Native - Zero Dependency)
# ==============================================================================

param(
    [int]$Port = 5000
)

$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = Get-Location }

$policiesPath = Join-Path $baseDir "config\policies.json"
$partnersPath = Join-Path $baseDir "config\existing_partners.json"
$candidatesPath = Join-Path $baseDir "samples\candidate_applications.json"
$indexPath = Join-Path $baseDir "public\index.html"
$secretPath = Join-Path $baseDir "config\secret.json"

# Ham tinh khoang cach GPS (Haversine formula in km)
function Get-DistanceKm($lat1, $lon1, $lat2, $lon2) {
    if (-not $lat1 -or -not $lon1 -or -not $lat2 -or -not $lon2) { return 9999.0 }
    $R = 6371.0 # Ban kinh trai dat tinh bang km
    $dLat = [Math]::PI / 180.0 * ($lat2 - $lat1)
    $dLon = [Math]::PI / 180.0 * ($lon2 - $lon1)
    $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) +
         [Math]::Cos([Math]::PI / 180.0 * $lat1) * [Math]::Cos([Math]::PI / 180.0 * $lat2) *
         [Math]::Sin($dLon / 2) * [Math]::Sin($dLon / 2)
    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
    return [Math]::Round(($R * $c), 2)
}

# Pipeline Tham dinh Multi-Agent cho 1 ho so ung vien
function Invoke-AgentEvaluation($candidate, $policies, $existingPartners) {
    $result = @{
        application_id = $candidate.application_id
        company_name = $candidate.company_name
        tax_id = $candidate.tax_id
        legal_rep = $candidate.legal_representative
        region = $candidate.region_applied
        status = "PENDING"
        total_score = 0
        decision = "REVIEW"
        agent_findings = @{
            entity_screening = @{}
            territory_check = @{}
            credit_check = @{}
            service_warranty_check = @{}
            purchase_feasibility = @{}
        }
        verification_conditions = @()
        flags = @()
    }

    # ----------------------------------------------------
    # AGENT 1: ENTITY DEDUPLICATION & BLACKLIST CHECK
    # ----------------------------------------------------
    $entityFindings = @{
        is_duplicate = $false
        is_blacklisted = $false
        matched_partner = $null
        details = "Hồ sơ pháp nhân độc lập, không trùng lặp."
    }

    foreach ($p in $existingPartners) {
        if ($p.tax_id -eq $candidate.tax_id -or $p.phone -eq $candidate.contact_phone -or ($p.legal_representative -and $p.legal_representative.ToLower() -eq $candidate.legal_representative.ToLower())) {
            $entityFindings.matched_partner = $p.name
            if ($p.status -eq "blacklisted_bad_debt") {
                $entityFindings.is_blacklisted = $true
                $entityFindings.details = "NGHIÊM TRỌNG: Trùng khớp thông tin (MST/Đại diện) với đối tác Blacklist [" + $p.name + "] - Lý do: " + $p.notes
                $result.flags += "BLACKLIST_MATCH: Đối tác từng phát sinh nợ xấu hoặc vi phạm hệ thống."
            } else {
                $entityFindings.is_duplicate = $true
                $entityFindings.details = "CẢNH BÁO: Trùng lặp với đối tác đang hoạt động [" + $p.name + "] trong hệ thống."
                $result.flags += "EXISTING_PARTNER: Đại lý này đã thuộc mạng lưới của Đại Thành."
            }
            break
        }
    }
    $result.agent_findings.entity_screening = $entityFindings

    # ----------------------------------------------------
    # AGENT 2: TERRITORY & PROTECTED RADIUS CHECK
    # ----------------------------------------------------
    $territoryFindings = @{
        has_conflict = $false
        conflicting_stores = @()
        score = 80
        summary = "Điểm bán đáp ứng khoảng cách an toàn."
    }

    $minAllowedRadius = $policies.territory_policy.protected_radius_km.urban_dense
    if (-not $minAllowedRadius) { $minAllowedRadius = 2.0 }

    if ($candidate.store_locations) {
        foreach ($appStore in $candidate.store_locations) {
            foreach ($partner in $existingPartners) {
                if ($partner.stores) {
                    foreach ($exStore in $partner.stores) {
                        $dist = Get-DistanceKm $appStore.lat $appStore.lng $exStore.lat $exStore.lng
                        $protRad = if ($exStore.protected_radius_km) { $exStore.protected_radius_km } else { $minAllowedRadius }
                        if ($dist -lt $protRad) {
                            $territoryFindings.has_conflict = $true
                            $conflictMsg = "Điểm [" + $appStore.address + "] cách showroom [" + $exStore.name + "] của [" + $partner.name + "] chỉ " + $dist + "km (Bán kính bảo hộ: " + $protRad + "km)."
                            $territoryFindings.conflicting_stores += $conflictMsg
                            $result.flags += "TERRITORY_CONFLICT: Xung đột địa bàn bảo hộ với đối tác hiện hữu."
                            $result.verification_conditions += "Cần thương lượng đổi vị trí điểm bán hoặc ký văn bản đồng thuận không phân vùng với đối tác " + $partner.name + "."
                        }
                    }
                }
            }
        }
    }

    if ($territoryFindings.has_conflict) {
        $territoryFindings.score = 30
        $territoryFindings.summary = "Phát hiện xung đột bán kính bảo hộ với đại lý hiện có."
    } else {
        $territoryFindings.score = 90
    }
    $result.agent_findings.territory_check = $territoryFindings

    # ----------------------------------------------------
    # AGENT 3: CREDIT & FINANCIAL RISK AUDIT
    # ----------------------------------------------------
    $creditReq = $candidate.commercial_requests.credit_limit_requested_vnd
    $graceDaysReq = $candidate.commercial_requests.grace_period_days_requested
    $probationPolicy = $policies.credit_policy.new_partner_probation

    $creditFindings = @{
        credit_requested = $creditReq
        grace_days_requested = $graceDaysReq
        exceeds_policy = $false
        score = 75
        details = ""
    }

    $maxCredit = $probationPolicy.max_credit_limit_vnd
    $maxGrace = $probationPolicy.max_grace_period_days
    $creditMio = [Math]::Round($creditReq / 1000000)

    if ($creditReq -gt $maxCredit -or $graceDaysReq -gt $maxGrace) {
        $creditFindings.exceeds_policy = $true
        $creditFindings.details = "Yêu cầu công nợ (" + $creditMio + " triệu, " + $graceDaysReq + " ngày) vượt khung thử việc của đối tác mới (Khung chuẩn: Tối đa 100 triệu, 7 ngày gối đầu)."
        $result.flags += "CREDIT_OVER_LIMIT: Đòi hỏi chính sách tài chính vượt khung quy định."
        $creditFindings.score = 40
        $result.verification_conditions += "Đàm phán lại điều khoản thanh toán: Yêu cầu 100% thanh toán trước đơn đầu, đơn sau gối đầu tối đa " + $maxGrace + " ngày hoặc cung cấp bảo lãnh ngân hàng."
    } else {
        $creditFindings.score = 85
        $creditFindings.details = "Chính sách công nợ đề xuất phù hợp quy chuẩn."
    }
    $result.agent_findings.credit_check = $creditFindings

    # ----------------------------------------------------
    # AGENT 4: OPERATIONS & SERVICE/WARRANTY CAPACITY
    # ----------------------------------------------------
    $w = $candidate.warranty_service_capacity
    $minTech = $policies.service_warranty_policy.min_technicians_per_store
    $maxSla = $policies.service_warranty_policy.max_sla_repair_hours
    $serviceFindings = @{
        technicians = if ($w) { $w.technicians_count } else { 0 }
        sla_hours = if ($w) { $w.average_sla_hours } else { 0 }
        meets_criteria = $true
        score = 80
        details = ""
    }

    if (-not $w -or $w.technicians_count -lt $minTech -or $w.average_sla_hours -gt $maxSla -or -not $w.has_service_center) {
        $serviceFindings.meets_criteria = $false
        $serviceFindings.details = "Chưa đáp ứng tiêu chuẩn dịch vụ sau bán: Có " + $serviceFindings.technicians + "/" + $minTech + " thợ, SLA cam kết " + $serviceFindings.sla_hours + "h (Quy chuẩn tối đa " + $maxSla + "h)."
        $serviceFindings.score = 35
        $result.flags += "SERVICE_CAPACITY_LOW: Năng lực bảo hành sửa chữa gia dụng chưa đạt chuẩn."
        $result.verification_conditions += "Khảo sát thực địa: Kiểm tra tay nghề kỹ thuật viên, yêu cầu cử ít nhất 2 nhân sự tham gia khóa đào tạo chứng chỉ kỹ thuật Đại Thành."
    } else {
        $serviceFindings.score = 90
        $serviceFindings.details = "Đội ngũ kỹ thuật và trạm dịch vụ đạt chuẩn bảo hành gia dụng."
    }
    $result.agent_findings.service_warranty_check = $serviceFindings

    # ----------------------------------------------------
    # AGENT 5: PURCHASE PLAN & TRADE SUPPORT FIT
    # ----------------------------------------------------
    $committedPurchase = if ($candidate.purchase_plan) { $candidate.purchase_plan.committed_monthly_volume_vnd } else { 0 }
    $purchaseFindings = @{
        committed_monthly = $committedPurchase
        score = 80
        summary = "Cam kết sản lượng khả thi so với quy mô điểm bán."
    }
    if ($committedPurchase -gt 1000000000 -and $serviceFindings.technicians -lt 2) {
        $purchaseFindings.score = 50
        $result.flags += "UNBALANCED_COMMITMENT: Cam kết nhập hàng lớn nhưng năng lực phục vụ khách hàng không tương xứng."
        $result.verification_conditions += "Yêu cầu đại lý cam kết tiến độ mở rộng trung tâm kỹ thuật song song với tiến độ doanh số."
    }
    $result.agent_findings.purchase_feasibility = $purchaseFindings

    # ----------------------------------------------------
    # SCORING & FINAL DECISION SYNTHESIS
    # ----------------------------------------------------
    $weights = $policies.scoring_weights
    $totalScore = (
        $territoryFindings.score * $weights.territory_feasibility +
        $creditFindings.score * $weights.financial_and_credit +
        $serviceFindings.score * $weights.service_warranty_capacity +
        $purchaseFindings.score * $weights.purchase_plan_credibility +
        80 * $weights.trade_support_fit
    )
    $result.total_score = [Math]::Round($totalScore, 1)

    # Quyet dinh
    if ($entityFindings.is_blacklisted) {
        $result.decision = "REJECTED"
        $result.status = "TỪ CHỐI NGAY (Blacklist/Gian lận)"
    } elseif ($territoryFindings.has_conflict -and $creditFindings.exceeds_policy -and -not $serviceFindings.meets_criteria) {
        $result.decision = "REJECTED"
        $result.status = "TỪ CHỐI (Vi phạm nhiều điều kiện cốt lõi)"
    } elseif ($result.flags.Count -gt 0 -or $result.verification_conditions.Count -gt 0) {
        $result.decision = "CONDITIONAL"
        $result.status = "CHỜ XÁC MINH & ĐÀM PHÁN LẠI"
    } else {
        $result.decision = "APPROVED"
        $result.status = "ƯU TIÊN TIẾN HÀNH KÝ HỢP ĐỒNG"
        $result.verification_conditions += "Tiến hành thị sát thẩm định thực tế điểm bán lần cuối trước khi ký."
    }

    return $result
}

# Khoi tao TCP Listener Server
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host " [AI AGENT] DAI THANH PARTNER EVALUATION SYSTEM IS RUNNING ON LOCALHOST!" -ForegroundColor Green
Write-Host " URL: http://localhost:$Port" -ForegroundColor Yellow
Write-Host " Thu muc lam viec: $baseDir" -ForegroundColor Gray
Write-Host " Nhan Ctrl+C de dung server." -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Cyan

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()

        try {
            # Doc byte tho tu stream cho den het header (\r\n\r\n)
            $rawBytes = [System.Collections.Generic.List[byte]]::new()
            $buf = [byte[]]::new(2048)
            $headerEndIndex = -1

            while ($true) {
                $bytesRead = $stream.Read($buf, 0, $buf.Length)
                if ($bytesRead -le 0) { break }
                for ($i = 0; $i -lt $bytesRead; $i++) {
                    $rawBytes.Add($buf[$i])
                }

                # Tim dau hieu \r\n\r\n (13, 10, 13, 10)
                $count = $rawBytes.Count
                for ($i = [Math]::Max(0, $count - $bytesRead - 4); $i -lt $count - 3; $i++) {
                    if ($rawBytes[$i] -eq 13 -and $rawBytes[$i+1] -eq 10 -and $rawBytes[$i+2] -eq 13 -and $rawBytes[$i+3] -eq 10) {
                        $headerEndIndex = $i
                        break
                    }
                }
                if ($headerEndIndex -ge 0) { break }
            }

            if ($headerEndIndex -lt 0) {
                $client.Close()
                continue
            }

            $headerBytes = $rawBytes.GetRange(0, $headerEndIndex).ToArray()
            $headerStr = [System.Text.Encoding]::ASCII.GetString($headerBytes)
            $headerLines = $headerStr -split "`r`n"
            $requestLine = $headerLines[0]

            $parts = $requestLine -split ' '
            $method = $parts[0]
            $urlPath = $parts[1]
            if ($urlPath -match '\?') {
                $urlPath = $urlPath.Substring(0, $urlPath.IndexOf('?'))
            }

            # Lay Content-Length
            $contentLength = 0
            foreach ($h in $headerLines) {
                if ($h -match "^Content-Length:\s*(\d+)") {
                    $contentLength = [int]$matches[1]
                }
            }

            # Lay cac bytes body da nam san trong buffer dau tien
            $bodyBytes = [System.Collections.Generic.List[byte]]::new()
            $bodyStart = $headerEndIndex + 4
            if ($rawBytes.Count -gt $bodyStart) {
                for ($i = $bodyStart; $i -lt $rawBytes.Count; $i++) {
                    $bodyBytes.Add($rawBytes[$i])
                }
            }

            # Neu chua du Content-Length bytes thi doc tiep dung so byte con thieu
            while ($bodyBytes.Count -lt $contentLength) {
                $toRead = $contentLength - $bodyBytes.Count
                $n = $stream.Read($buf, 0, [Math]::Min($buf.Length, $toRead))
                if ($n -le 0) { break }
                for ($i = 0; $i -lt $n; $i++) {
                    $bodyBytes.Add($buf[$i])
                }
            }

            $body = ""
            if ($bodyBytes.Count -gt 0) {
                $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes.ToArray())
            }

            Write-Host "[HTTP] $method $urlPath (Body: $($bodyBytes.Count) bytes)" -ForegroundColor DarkGray

            # Xu ly cac Routes
            $statusCode = "200 OK"
            $contentType = "text/html; charset=utf-8"
            $responseBytes = [byte[]]@()

            if ($method -eq "OPTIONS") {
                $responseHeader = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: 0`r`n`r`n"
                $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($responseHeader)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                $client.Close()
                continue
            }

            $cleanPath = $urlPath.TrimStart('/')
            if ($cleanPath -eq "" -or $cleanPath -eq "index.html") { $cleanPath = "index.html" }
            $candidateFile = Join-Path (Join-Path $baseDir "public") $cleanPath.Replace('/', '\')

            if ($method -eq "GET" -and (Test-Path $candidateFile -PathType Leaf)) {
                $ext = [System.IO.Path]::GetExtension($candidateFile).ToLower()
                $contentType = switch ($ext) {
                    ".html" { "text/html; charset=utf-8" }
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".webp" { "image/webp" }
                    ".svg"  { "image/svg+xml" }
                    ".css"  { "text/css; charset=utf-8" }
                    ".js"   { "application/javascript; charset=utf-8" }
                    default { "application/octet-stream" }
                }
                $responseBytes = [System.IO.File]::ReadAllBytes($candidateFile)
                $statusCode = "200 OK"
            }
            elseif ($urlPath -eq "/api/policies" -and $method -eq "GET") {
                $policiesJson = Get-Content -Path $policiesPath -Raw -Encoding UTF8
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($policiesJson)
                $contentType = "application/json; charset=utf-8"
            }
            elseif ($urlPath -eq "/api/partners" -and $method -eq "GET") {
                $partnersJson = Get-Content -Path $partnersPath -Raw -Encoding UTF8
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($partnersJson)
                $contentType = "application/json; charset=utf-8"
            }
            elseif ($urlPath -eq "/api/candidates" -and $method -eq "GET") {
                $candidatesJson = Get-Content -Path $candidatesPath -Raw -Encoding UTF8
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($candidatesJson)
                $contentType = "application/json; charset=utf-8"
            }
            elseif ($urlPath -eq "/api/config" -and $method -eq "GET") {
                if (Test-Path $secretPath) {
                    $secretJson = Get-Content -Path $secretPath -Raw -Encoding UTF8
                } else {
                    $secretJson = '{"gemini_api_key": ""}'
                }
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($secretJson)
                $contentType = "application/json; charset=utf-8"
            }
            elseif ($urlPath -eq "/api/evaluate-all" -and ($method -eq "GET" -or $method -eq "POST")) {
                $policies = (Get-Content -Path $policiesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                $partners = (Get-Content -Path $partnersPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                $candidates = (Get-Content -Path $candidatesPath -Raw -Encoding UTF8 | ConvertFrom-Json)

                $evaluationResults = @()
                foreach ($cand in $candidates) {
                    $evaluationResults += (Invoke-AgentEvaluation $cand $policies $partners)
                }

                $jsonOutput = ($evaluationResults | ConvertTo-Json -Depth 10)
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonOutput)
                $contentType = "application/json; charset=utf-8"
            }
            elseif ($urlPath -eq "/api/evaluate-single" -and $method -eq "POST") {
                $candidateInput = ($body | ConvertFrom-Json)
                $policies = (Get-Content -Path $policiesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                $partners = (Get-Content -Path $partnersPath -Raw -Encoding UTF8 | ConvertFrom-Json)

                # Luu ho so moi vao danh sach de luu tru
                try {
                    $allCandidates = (Get-Content -Path $candidatesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                    $allCandidates = @($candidateInput) + $allCandidates
                    $allCandidates | ConvertTo-Json -Depth 10 | Set-Content -Path $candidatesPath -Encoding UTF8
                } catch {
                    Write-Host "Warning: Could not save candidate to file: $_" -ForegroundColor Yellow
                }

                $evalResult = Invoke-AgentEvaluation $candidateInput $policies $partners
                $jsonOutput = ($evalResult | ConvertTo-Json -Depth 10)
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonOutput)
                $contentType = "application/json; charset=utf-8"
            }
            else {
                $statusCode = "404 Not Found"
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
                $contentType = "text/plain; charset=utf-8"
            }

            $headerText = "HTTP/1.1 $statusCode`r`n" +
                          "Content-Type: $contentType`r`n" +
                          "Content-Length: $($responseBytes.Length)`r`n" +
                          "Access-Control-Allow-Origin: *`r`n" +
                          "Connection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerText)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            if ($responseBytes.Length -gt 0) {
                $stream.Write($responseBytes, 0, $responseBytes.Length)
            }
            $stream.Flush()
        } catch {
            Write-Host "Loi xu ly request: $_" -ForegroundColor Red
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
