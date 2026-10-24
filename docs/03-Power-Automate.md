# 03 — Power Automate: các flow

Flow là **backend** của hệ thống: toàn bộ thao tác làm thay đổi dữ liệu đi qua đây, chạy bằng tài khoản dịch vụ, có kiểm tra phía server. Power Apps chỉ là giao diện.

## 1. Danh mục flow

| Mã | Tên flow | Loại | Ai gọi | Mục đích |
|---|---|---|---|---|
| **LAB-F01** | `LAB-F01 RegisterIncoming` | Instant (Power Apps V2) | Admin, Analyst | Đăng ký hoá chất đầu vào: tạo N chai + mã + sổ cái |
| **LAB-F02** | `LAB-F02 CreatePreparation` | Instant | Admin, Analyst | Đăng ký pha chế: tạo dung dịch + công thức + trừ tồn nguồn |
| **LAB-F03** | `LAB-F03 RecordUsage` | Instant | Admin, Analyst | Ghi nhận sử dụng / gắn hoá chất vào biên bản thử nghiệm |
| **LAB-F04** | `LAB-F04 AdminAction` | Instant | Admin (Release/Review: Reviewer) | Điều chỉnh, huỷ bỏ, vô hiệu, release, duyệt |
| **LAB-C01** | `LAB-C01 PostTransaction` | Child flow | F01–F04 | Cổng duy nhất ghi sổ cái + cập nhật số dư/trạng thái |
| **LAB-S01** | `LAB-S01 DailyExpiryStock` | Scheduled 07:00 | — | Đánh dấu hết hạn, cảnh báo sắp hết hạn / dưới tồn tối thiểu |
| **LAB-S02** | `LAB-S02 Reconcile` | Scheduled 02:00 | — | Đối soát cache với sổ cái, sửa lệch, phát hiện bản ghi dở dang |

Giai đoạn 2 (chưa thiết kế chi tiết): duyệt nhập kho bằng Approvals, thông báo duyệt dung dịch qua Teams, sinh PDF nhãn, xuất báo cáo truy xuất PDF/Excel, upload COA.

## 2. Quy ước chung

### 2.1 Triển khai
- Đặt toàn bộ flow trong **một Solution** (ALM Dev → Test → Prod). Child flow **bắt buộc** nằm trong solution cùng flow cha. Solution cần environment có Dataverse; nếu tenant chỉ có Default environment không dùng solution được, thì thay `LAB-C01` bằng một *Scope* sao chép vào từng flow (chấp nhận lặp logic).
- Chủ sở hữu flow: **tài khoản dịch vụ** `svc-labchem` (không dùng tài khoản cá nhân), thêm 2 co-owner là Admin lab. Tài khoản này là *chủ sở hữu connection* SharePoint/Outlook.
- Trong *Run only users* của các instant flow: đặt connection SharePoint = **"Use this connection (svc-labchem)"**, không chọn "Provided by run-only user" — người dùng chỉ có quyền *Read* trên list, nên quyền ghi phải đến từ tài khoản dịch vụ.
- Địa chỉ site và tên list đặt trong **Environment variables** của solution (`SiteUrl`, ...), không hard-code.
- Chỉ dùng connector *Standard* (SharePoint, Office 365 Outlook, Approvals, Teams). Không dùng HTTP (Premium).

### 2.2 Khối chuẩn ở đầu mỗi flow F01–F04

| # | Action | Chi tiết |
|---|---|---|
| 0.1 | Trigger **PowerApps (V2)** | 1 input `payload` (Text) chứa JSON. Một input duy nhất giúp đổi schema không phải gắn lại flow vào app. |
| 0.2 | Compose `caller` | `toLower(base64ToString(triggerOutputs()?['headers']?['x-ms-user-email-encoded']))` — danh tính người gọi **lấy từ phía server**, không bao giờ tin email do app gửi lên. Nếu tenant không có header này: dùng *Office 365 Users → My profile (V2)* với connection "run-only user", rồi lấy `Mail`. (Kiểm thử T-SEC-01.) |
| 0.3 | Compose `nowLocal` | `convertTimeZone(utcNow(),'UTC','SE Asia Standard Time')` |
| 0.4 | **Parse JSON** `payload` | Schema theo từng flow bên dưới (cho phép `null` ở trường tuỳ chọn). Lỗi parse → Respond `success=false`. Kiểm `requestId`: đúng 36 ký tự, chỉ gồm `0-9a-f-` (`length(...)=36` và không chứa dấu nháy) — nó được dùng trong `$filter` nên phải sạch. |
| 0.5 | **Idempotency** | Get items `LabAudit` — Filter `RequestId eq '<requestId>' and Result eq 'Success'`, Top 1. Nếu có: Respond lại kết quả đã lưu trong `Detail` rồi **Terminate**. Chặn ghi trùng khi người dùng bấm hai lần hoặc app gọi lại do timeout. |
| 0.6 | **Kiểm tra vai trò** | Get items `LabRoles` — Filter `Title eq '<caller>' and IsActive eq 1`, Top 1. Không có hoặc vai trò không thuộc danh sách cho phép → ghi `LabAudit` (Rejected, "Không đủ quyền") → Respond `success=false` → Terminate. |
| 0.7 | **Scope `Try`** … **Scope `Catch`** | `Catch` chạy khi `Try` Failed/TimedOut: ghi `LabAudit` (Error, `workflow()['run']['name']` vào `RunId`), Respond thông báo chung "Có lỗi hệ thống, mã tham chiếu <RunId>". **Không trả chi tiết lỗi kỹ thuật cho client.** |

**Quy tắc `$filter`:** truy vấn SharePoint trong flow lọc bằng `ID` (số) hoặc mã đã kiểm định dạng. Chuỗi do người dùng nhập (tên, số lô, ghi chú, số biên bản) chỉ được **ghi** vào cột, không được nối vào `$filter`; nếu bắt buộc (ví dụ tìm theo `reportNo`), escape dấu nháy đơn bằng `replace(x, '''', '''''')`.

### 2.3 Hợp đồng phản hồi (Respond to a PowerApp or flow)

| Output | Kiểu | Ý nghĩa |
|---|---|---|
| `success` | Yes/No | Thành công hay không |
| `message` | Text | Thông báo tiếng Việt hiển thị thẳng cho người dùng |
| `codes` | Text | Các mã tạo ra, phân tách bằng dấu phẩy (F01: mã chai, F02: mã dung dịch) |

Mọi nhánh từ chối nghiệp vụ trả `success=false` + `message` rõ nguyên nhân (ví dụ "IN-26-00041: không đủ lượng, còn 12,5 g") và **luôn ghi `LabAudit`**.

### 2.4 Ghi chú vận hành
- **Lịch sử chạy của flow chỉ lưu khoảng 28 ngày** → bằng chứng kiểm toán lâu dài nằm ở `LabAudit` + `LabLedger` + version history, không nằm ở run history.
- Instant flow không có *Concurrency control* nên hai lần gọi có thể chạy song song; thiết kế xử lý bằng cơ chế kiểm tra lại sau khi ghi trong `LAB-C01` và đối soát `LAB-S02` (mục 4 và 9).
- Power Apps chờ phản hồi flow tối đa khoảng 2 phút; thiết kế giữ mỗi flow dưới ~30 giây ở điều kiện thường (F01 dùng song song 5 luồng).
- Hạn mức API / số action mỗi ngày phụ thuộc giấy phép của tenant và tính theo tài khoản dịch vụ — cần IT xác nhận. Quy mô lab (vài trăm thao tác/ngày, ~5–30 action/thao tác) rất nhỏ so với hạn mức thông thường, nhưng `LAB-S02` nên chạy gia tăng (mục 9).

---

## 3. LAB-F01 RegisterIncoming

**Vai trò được phép:** Admin, Analyst.

**Payload**
```json
{
  "requestId": "guid",
  "catalogId": 12,
  "mfgLot": "AB1234",
  "manufacturer": "Merck",
  "supplier": "Công ty X",
  "receivedDate": "2026-10-24",
  "mfgDate": "2026-03-01",
  "expiryDate": "2028-03-01",
  "qty": 500,
  "unit": "mL",
  "bottleCount": 3,
  "locationId": 5,
  "coaLink": "https://contoso.sharepoint.com/sites/LabChem/COA/AB1234.pdf",
  "note": ""
}
```
`qty` là lượng **mỗi chai**, đã quy đổi về đơn vị gốc.

**Các bước**

1. Khối chuẩn 0.1–0.7 (vai trò: Admin, Analyst).
2. Đọc `LabSettings`: `MaxBottlesPerReceipt`, `RequireIncomingRelease`, `ReportUrlAllowedHosts` (nếu dùng cho `coaLink`).
3. Get item `LabCatalog` theo `catalogId`.
4. **Kiểm tra** — gom lỗi vào mảng `errors`, nếu có lỗi thì Rejected:
   - danh mục tồn tại và `IsActive`;
   - `unit` = `BaseUnit` của danh mục;
   - `qty` > 0; `1 ≤ bottleCount ≤ MaxBottlesPerReceipt`;
   - `receivedDate` không ở tương lai; `mfgDate ≤ receivedDate`; `expiryDate > receivedDate` (không nhận hoá chất đã hết hạn);
   - `coaLink` rỗng hoặc bắt đầu `https://` (và đúng host cho phép nếu có cấu hình);
   - `locationId` rỗng hoặc tồn tại và `IsActive`.
5. Biến `initialStatus` = `Quarantine` nếu `RequireIncomingRelease` = `true`, ngược lại `Available`.
6. **Apply to each** trên `range(0, bottleCount)` — *Concurrency control = 5* (mỗi vòng độc lập nhờ mã sinh từ `ID`):
   1. **Create item** `LabLots`: `Title = guid()`, các cột snapshot (`ChemName`, `CasNumber` từ danh mục; `LocationName` từ vị trí), `InitialQty = RemainingQty = qty`, `Status = initialStatus`, `RegisteredBy = caller`.
   2. **Update item** `Title = concat('IN-', formatDateTime(outputs('nowLocal'),'yy'), '-', formatNumber(outputs('Create_Lot')?['body/ID'], '00000'))`.
   3. **Create item** `LabLedger`: `ItemType=Lot`, `ItemID=ID`, `TxnType=Receive`, `QtyDelta=qty`, `BalanceAfter=qty`, `Actor=caller`.
   4. **Append to array variable** `codes`.
   (Giao dịch `Receive` ghi trực tiếp, không qua `LAB-C01` vì chưa có số dư trước đó.)
7. **Create item** `LabAudit`: `Title=RegisterIncoming`, `Result=Success`, `RequestId`, `Detail={"codes":[...]}`, `EntityCode` = mã đầu tiên.
8. **Respond**: `success=true`, `message="Đã tạo @{length(variables('codes'))} chai"`, `codes=join(sort(variables('codes')),',')`.

**Lỗi dở dang:** nếu lỗi xảy ra giữa bước 6.1 và 6.3 thì có thể tồn tại chai có `Title` dạng GUID hoặc thiếu dòng sổ cái. `LAB-S02` quét và sửa/cảnh báo các trường hợp này (mục 9).

---

## 4. LAB-C01 PostTransaction (child flow) — "cổng ghi sổ cái"

Mọi biến động `PrepUse`, `TestUse`, `PrepCreate`, `Adjust`, `Dispose`, `Reversal` đi qua flow này. Đặt toàn bộ logic số dư/trạng thái ở **một chỗ**.

**Trigger:** *Manually trigger a flow* — inputs: `itemType` (`Lot`|`Prep`), `itemId`, `txnType`, `qtyDelta` (số, âm = xuất), `unit`, `refType`, `refCode`, `reason`, `actor` (email).

**Output:** `ok` (Yes/No), `balance` (số), `status` (text), `message`.

**Các bước**

1. Get item cha (`LabLots` hoặc `LabPreps` theo `itemType`): `RemainingQty`, `InitialQty`/`FinalQty`, `Unit`, `Status`, `ExpiryDate`, `Title`.
2. Kiểm tra `unit` = `Unit` của cha (BR-04), nếu sai → `ok=false`.
3. **Tính số dư từ sổ cái:** Get items `LabLedger` — Filter `ItemType eq '<t>' and ItemID eq <id>`, Top 5000 (bật pagination). Initialize `sum` (Float) = 0 → Apply to each → *Increment variable* `sum` bằng `items('…')?['QtyDelta']`.
4. `newBalance = float(formatNumber(add(variables('sum'), qtyDelta), '0.0000'))`.
5. Nếu `newBalance < -0.00005` → trả `ok=false`, `message="Không đủ lượng: còn <sum> <unit>"` (**không ghi gì**).
6. **Create item** `LabLedger`: `Title=<mã cha>`, `QtyDelta`, `BalanceAfter=newBalance`, `RefType`, `RefCode`, `Reason`, `Actor`.
7. **Kiểm tra lại sau khi ghi** (chống đua): tính lại tổng `sum2` từ sổ cái như bước 3.
   - Nếu `sum2 ≠ newBalance`: có giao dịch khác chen vào. Cập nhật `BalanceAfter` của dòng vừa ghi = `sum2`, đặt `newBalance = sum2`.
   - Nếu `sum2 < -0.00005`: ghi ngay một dòng `Reversal` bù (+`qtyDelta`), gửi cảnh báo cho Admin, trả `ok=false`, `message="Xung đột đồng thời, giao dịch đã bị huỷ — thử lại"`.
8. **Update item cha:**
   - `RemainingQty = newBalance`
   - `Status`: giữ nguyên nếu đang `Disposed` hoặc `Quarantine`; nếu `txnType = Dispose` → `Disposed`; nếu `newBalance ≤ 0.00005` → `Empty`; nếu `ExpiryDate < hôm nay` → `Expired`; nếu `newBalance < InitialQty` (hoặc `FinalQty`) → `InUse`; ngược lại `Available`.
   - Với `Lot`: nếu `OpenedDate` trống và `txnType ∈ {PrepUse, TestUse}` → `OpenedDate = hôm nay`.
9. Respond `ok=true`, `balance`, `status`.

> **Giới hạn đã biết:** vì instant flow không có concurrency control, nếu hai người cùng trừ **cùng một chai** trong khoảng vài giây, bước 7 phát hiện và bù lại; cửa sổ đua còn lại cực nhỏ và được `LAB-S02` quét hằng đêm. Với quy mô phòng lab, rủi ro này chấp nhận được; nếu cần tuyệt đối, chuyển sang khoá bản ghi bằng cột `LockedBy` hoặc dùng Dataverse.

---

## 5. LAB-F02 CreatePreparation

**Vai trò được phép:** Admin, Analyst.

**Payload**
```json
{
  "requestId": "guid",
  "prepName": "NaOH 0,1 N",
  "prepType": "Dung dịch làm việc",
  "concentration": "0.1 mol/L",
  "sopRef": "SOP-QC-014",
  "procedure": "Hoà tan 4,0 g NaOH trong 1000 mL nước cất ...",
  "prepDate": "2026-10-24",
  "expiryDate": "2026-11-24",
  "finalQty": 1000,
  "unit": "mL",
  "locationId": 5,
  "storageCondition": "15-25 °C (phòng)",
  "note": "",
  "items": [
    { "sourceType": "Lot",  "sourceId": 42, "qty": 4.0,    "role": "Chất tan" },
    { "sourceType": "Lot",  "sourceId": 57, "qty": 1000,   "role": "Dung môi" }
  ]
}
```
`items[].qty` đã quy đổi về đơn vị gốc của từng nguồn.

**Các bước**

1. Khối chuẩn 0.1–0.7 (Admin, Analyst).
2. **Kiểm tra phần đầu:** `prepName` không rỗng; `finalQty > 0`; `prepDate` không ở tương lai và không quá cũ hơn 7 ngày (Admin được bỏ qua giới hạn này); `expiryDate > prepDate`; `1 ≤ items ≤ 30`; không có hai dòng trùng (`sourceType`+`sourceId`) — so `length(union(...))` với `length(items)`; mọi `qty > 0`.
3. **Với từng dòng thành phần** (Apply to each, tuần tự): Get item nguồn theo `sourceType`, kiểm tra
   - BR-03: `Status ∈ {Available, InUse}`, `ExpiryDate ≥ prepDate`, `IsVoid = false`; nếu nguồn là `Prep` thì `ReviewStatus ≠ Rejected`;
   - `qty ≤ RemainingQty` (kiểm tra sơ bộ trên cache);
   - ghi vào mảng `resolved`: id, mã, tên, số lô NSX, đơn vị, `qty`, `role`, `ExpiryDate`.
   Lỗi nào cũng thêm vào mảng `errors` dạng `"<mã>: <lý do>"`.
4. Nếu `errors` không rỗng → `LabAudit` (Rejected, `Detail=errors`) → Respond `success=false`, `message=join(errors,'; ')`.
5. Nếu `EnforcePrepExpiryLimit = true` và `expiryDate > hạn sớm nhất của resolved` → Rejected với thông báo nêu mã thành phần giới hạn hạn dùng.
6. **Create item** `LabPreps` (`Title=guid()`, `RemainingQty=0`, `Status=Available`, `ReviewStatus=Pending`, `PreparedBy=caller`, snapshot `LocationName`) → **Update** `Title = 'PC-' & yy & '-' & formatNumber(ID,'00000')`.
7. **Với từng dòng `resolved`** (tuần tự, biến `failed=false`):
   1. Create item `LabPrepItems` (`Title=PrepCode`, `PrepID`, nguồn + snapshot).
   2. Run child flow **LAB-C01** (`PrepUse`, `-qty`, `RefType=Prep`, `RefCode=PrepCode`).
   3. Nếu `ok=false` → `failed=true`, lưu thông báo, **thoát vòng lặp** (các dòng sau bỏ qua).
8. Nếu `failed`: **rollback** — với mỗi dòng đã trừ thành công gọi `LAB-C01` loại `Reversal` (+`qty`, lý do "Rollback tạo <PrepCode>"); cập nhật dung dịch `IsVoid=true`, `Status=Disposed`, `VoidReason`; ghi `LabAudit` (Rejected) → Respond `success=false`.
9. Nếu không lỗi: Run `LAB-C01` (`PrepCreate`, `+finalQty` trên chính dung dịch) → số dư dung dịch = `finalQty`.
10. `LabAudit` Success (`Detail={"codes":["PC-26-00017"]}`) → Respond `success=true`, `codes=<PrepCode>`.

---

## 6. LAB-F03 RecordUsage

**Vai trò được phép:** Admin, Analyst. Dùng để *gắn hoá chất vào biên bản thử nghiệm* (yêu cầu truy xuất) và ghi nhận dùng cho mục đích khác.

**Payload**
```json
{
  "requestId": "guid",
  "purpose": "Test",
  "reportNo": "BB-2026-0153",
  "reportUrl": "https://contoso.sharepoint.com/sites/QA/Reports/BB-2026-0153.pdf",
  "testName": "Chuẩn độ acid-base",
  "sampleCode": "M-26-0899",
  "usedDate": "2026-10-24T09:30:00",
  "note": "",
  "lines": [
    { "itemType": "Prep", "itemId": 17, "qty": 25 },
    { "itemType": "Lot",  "itemId": 61, "qty": 2 }
  ]
}
```

**Các bước**

1. Khối chuẩn 0.1–0.7 (Admin, Analyst).
2. **Kiểm tra:** `purpose ∈ {Test, Other}`; `purpose=Test` ⇒ `reportNo` bắt buộc (≤ 100 ký tự); `purpose=Other` ⇒ `note` bắt buộc (lý do); `reportUrl` rỗng hoặc bắt đầu `https://` và (nếu `ReportUrlAllowedHosts` có cấu hình) hậu tố host nằm trong danh sách — chặn `javascript:`/`data:` và liên kết ra ngoài; `usedDate` không ở tương lai; `1 ≤ lines ≤ 20`, không trùng dòng, `qty > 0`.
3. **Với từng dòng:** Get đối tượng, kiểm tra BR-03, BR-04, `qty ≤ RemainingQty`. Gom lỗi như F02; có lỗi → Rejected, **chưa ghi gì**.
4. **Với từng dòng** (tuần tự): Run `LAB-C01` (`TestUse`, `-qty`, `RefType = Report` nếu `Test` ngược lại `Manual`, `RefCode = reportNo`, `Reason = note`). Nếu có dòng `ok=false` → rollback các dòng trước bằng `Reversal` → Rejected.
5. Chỉ khi mọi dòng đã trừ thành công và `purpose=Test`: Create item `LabTestUsage` cho từng dòng (`Title=reportNo`, `ReportUrl`, `TestName`, `SampleCode`, `ItemType/ItemID/ItemCode/ItemName`, `QtyUsed`, `Unit`, `UsedDate`, `Analyst=caller`).
   Tạo `LabTestUsage` **sau** khi trừ tồn thành công vì list này không cho xoá; nếu bước này lỗi, `LAB-S02` phát hiện dòng sổ cái `RefType=Report` thiếu `LabTestUsage` và cảnh báo.
6. `LabAudit` Success → Respond `success=true`, `message="Đã ghi nhận <n> dòng cho biên bản <reportNo>"`.

---

## 7. LAB-F04 AdminAction

**Payload:** `{ requestId, action, itemType, itemId, newQty, decision, reason }`

| `action` | Vai trò | Điều kiện | Việc làm |
|---|---|---|---|
| `Adjust` | Admin | `reason` ≥ 10 ký tự; `newQty ≥ 0`; khác số dư hiện tại | `LAB-C01` `Adjust` với `qtyDelta = newQty − số dư` |
| `Dispose` | Admin | `reason` bắt buộc; còn tồn | `LAB-C01` `Dispose` với `-số dư` → `Status=Disposed` |
| `Void` | Admin | `reason` bắt buộc; **không** có hậu duệ: Get `LabPrepItems` (`SourceType`,`SourceID`) và `LabTestUsage` (`ItemType`,`ItemID`) đều rỗng | `LAB-C01` `Reversal` về 0; đặt `IsVoid=true`, `Status=Disposed`, `VoidReason`. Nếu có hậu duệ → từ chối, hướng dẫn dùng `Dispose` |
| `Release` | Reviewer, Admin | `itemType=Lot` và `Status=Quarantine` | `Status=Available`; ghi audit |
| `Review` | Reviewer, Admin | `itemType=Prep`; `decision ∈ {Approved, Rejected}`; `ReviewedBy ≠ PreparedBy` (BR-08); `Rejected` ⇒ `reason` bắt buộc | `ReviewStatus`, `ReviewedBy=caller`, `ReviewedOn=now` |

Mọi `action` đều ghi `LabAudit` kèm `reason`, kể cả khi bị từ chối.

---

## 8. LAB-S01 DailyExpiryStock (Recurrence 07:00 giờ Việt Nam)

1. Đọc `ExpiryWarnDays` (mặc định 30), `AlertEmails`.
2. **Đánh dấu hết hạn:** Get `LabLots` và `LabPreps` — Filter `(Status eq 'Available' or Status eq 'InUse') and ExpiryDate lt '<hôm nay>'` → Update `Status=Expired`. Ghi một dòng `LabAudit` tổng kết.
3. **Sắp hết hạn:** cùng bộ lọc với `ExpiryDate ge '<hôm nay>' and ExpiryDate le '<hôm nay + N>'` → *Create HTML table* (mã, tên, số lô, hạn dùng, còn lại, vị trí).
4. **Dưới tồn tối thiểu:** Get `LabCatalog` — `IsActive eq 1 and MinStockQty gt 0`; với mỗi dòng Get `LabLots` — `CatalogID eq <id> and (Status eq 'Available' or Status eq 'InUse')`, cộng `RemainingQty`; nếu < `MinStockQty` thì thêm vào bảng.
5. Nếu có ít nhất một mục: **Send an email (V2)** tới `AlertEmails` (HTML gọn: 3 bảng + link mở app).
6. Phase 2: thêm bài đăng Teams; ghi snapshot KPI vào `LabSettings` khi dữ liệu vượt ngưỡng delegation.

## 9. LAB-S02 Reconcile (Recurrence 02:00)

Chạy **gia tăng mỗi đêm**, **toàn bộ mỗi Chủ nhật**.

1. Tập cần kiểm: gia tăng = các `(ItemType, ItemID)` có dòng `LabLedger` với `Created ge now−2 ngày` (loại trùng); toàn bộ = mọi `LabLots`/`LabPreps` chưa `Disposed`.
2. Với từng đối tượng: tính Σ `QtyDelta`; so với `RemainingQty`. Lệch > 0.00005 → sửa cache bằng giá trị từ sổ cái, ghi `LabAudit` (Result=Error, "Reconcile mismatch", giá trị cũ/mới), gom vào email cho Admin. Sổ cái luôn thắng.
3. **Bản ghi dở dang:** `Title` còn là GUID (không khớp `IN-yy-nnnnn` / `PC-yy-nnnnn`) → sinh lại mã từ `ID` và cảnh báo; chai thiếu dòng `Receive`; dòng sổ cái `RefType=Report` không có `LabTestUsage` tương ứng → cảnh báo Admin xử lý.
4. Tổng kết một dòng `LabAudit` (`System`, số đối tượng đã kiểm, số lệch).

## 10. Việc cần làm khi dựng flow

- Đặt tên action có nghĩa (`Create_Lot`, `Create_Ledger_Receive`...) vì biểu thức tham chiếu theo tên.
- Bật *Secure inputs/outputs* cho các action chứa email/Detail nếu tenant có yêu cầu bảo mật log.
- Mỗi flow có action "Terminate" ở mọi nhánh từ chối để không chạy tiếp.
- Gắn flow vào app: *Power Apps → Power Automate → Add flow*; vì dùng một input `payload` nên đổi schema chỉ cần sửa JSON ở hai đầu.
