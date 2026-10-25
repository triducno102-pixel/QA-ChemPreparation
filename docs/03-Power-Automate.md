# 03 — Power Automate: các flow

Flow là **backend** của hệ thống: toàn bộ thao tác làm thay đổi dữ liệu đi qua đây, chạy bằng tài khoản dịch vụ, có kiểm tra phía server và **luôn để lại nhật ký**. Power Apps chỉ là giao diện.

## 1. Danh mục flow

| Mã | Tên flow | Loại | Ai gọi | Mục đích |
|---|---|---|---|---|
| **LAB-F01** | `LAB-F01 RegisterIncoming` | Instant (Power Apps V2) | Admin, Analyst | Đăng ký hoá chất đầu vào: tạo N chai + mã + sổ cái |
| **LAB-F02** | `LAB-F02 CreatePreparation` | Instant | Admin, Analyst | Đăng ký pha chế: tạo dung dịch + công thức + trừ tồn nguồn |
| **LAB-F03** | `LAB-F03 RecordUsage` | Instant | Admin, Analyst | Ghi nhận sử dụng / gắn hoá chất vào biên bản thử nghiệm |
| **LAB-F04** | `LAB-F04 AdminAction` | Instant | Admin (Release/Review: Reviewer) | Điều chỉnh, huỷ bỏ, vô hiệu, release, duyệt |
| **LAB-F05** | `LAB-F05 AdminData` | Instant | Admin | Sửa danh mục, vị trí, cấu hình, vai trò — **đường duy nhất** để đổi dữ liệu gốc, có trước/sau và lý do |
| **LAB-F06** | `LAB-F06 LogEvent` | Instant | Mọi người dùng | Ghi sự kiện do app báo: in nhãn, mở màn Nhật ký, bị từ chối vào app |
| **LAB-C01** | `LAB-C01 PostTransaction` | Child flow | F01–F04 | Cổng duy nhất ghi sổ cái + cập nhật số dư/trạng thái |
| **LAB-C02** | `LAB-C02 WriteAudit` | Child flow | F01–F06, S01–S03 | **Cổng duy nhất ghi `LabAudit`**: kiểm định dạng, ghi nhiều dòng, thử lại |
| **LAB-S01** | `LAB-S01 DailyExpiryStock` | Scheduled 07:00 | — | Đánh dấu hết hạn, cảnh báo sắp hết hạn / sắp hết (dưới ngưỡng %), báo cáo sự kiện Critical hằng ngày |
| **LAB-S02** | `LAB-S02 Reconcile` | Scheduled 02:00 | — | Đối soát cache với sổ cái, sửa lệch, phát hiện bản ghi dở dang |
| **LAB-S03** | `LAB-S03 IntegrityWatch` | Scheduled 03:30 | — | Giám sát nhật ký và sổ cái: yêu cầu thiếu cặp Started–kết thúc, dòng bị sửa/xoá, thay đổi quyền ngoài app |

Giai đoạn 2 (chưa thiết kế chi tiết): duyệt nhập kho bằng Approvals, thông báo duyệt dung dịch qua Teams, sinh PDF nhãn, xuất báo cáo truy xuất PDF/Excel, upload COA.

## 2. Quy ước chung

### 2.1 Triển khai
- Đặt toàn bộ flow trong **một Solution** (ALM Dev → Test → Prod). Child flow (`LAB-C01`, `LAB-C02`) **bắt buộc** nằm trong solution cùng flow cha. Solution cần environment có Dataverse; nếu tenant chỉ có Default environment không dùng solution được, thì thay `LAB-C01`/`LAB-C02` bằng một *Scope* sao chép vào từng flow (chấp nhận lặp logic).
- Chủ sở hữu flow: **tài khoản dịch vụ** `svc-labchem` (không dùng tài khoản cá nhân), thêm 2 co-owner là Admin lab. Tài khoản này là *chủ sở hữu connection* SharePoint/Outlook.
- Trong *Run only users* của các instant flow: đặt connection SharePoint = **"Use this connection (svc-labchem)"**, không chọn "Provided by run-only user" — người dùng chỉ có quyền *Read* trên list, nên quyền ghi phải đến từ tài khoản dịch vụ. **Không chia sẻ `LAB-C01`/`LAB-C02` cho người dùng**: chúng tin `actor` do flow cha truyền vào.
- Địa chỉ site và tên list đặt trong **Environment variables** của solution (`SiteUrl`, ...), không hard-code.
- Chỉ dùng connector *Standard* (SharePoint, Office 365 Outlook, Approvals, Teams). Không dùng action HTTP chung (Premium). Riêng action **"Send an HTTP request to SharePoint"** (thuộc connector SharePoint, Standard) được dùng ở `LAB-S03` để đọc thuộc tính list và nhóm.

### 2.2 Khối chuẩn ở đầu mỗi flow F01–F05

Thứ tự này là cố ý: **ghi dấu vết trước, làm việc sau**.

| # | Action | Chi tiết |
|---|---|---|
| 0.1 | Trigger **PowerApps (V2)** | 1 input `payload` (Text) chứa JSON. Một input duy nhất giúp đổi schema không phải gắn lại flow vào app. |
| 0.2 | Compose `caller` | `toLower(base64ToString(triggerOutputs()?['headers']?['x-ms-user-email-encoded']))` — danh tính người gọi **lấy từ phía server**, không bao giờ tin email do app gửi lên. Nếu tenant không có header này: dùng *Office 365 Users → My profile (V2)* với connection "run-only user", rồi lấy `Mail`. (Kiểm thử T-SEC-01.) |
| 0.3 | Compose `nowLocal` | `convertTimeZone(utcNow(),'UTC','SE Asia Standard Time')` |
| 0.4 | **Parse JSON** `payload` | Trường chung của mọi payload: `requestId` (đúng 36 ký tự, chỉ gồm `0-9a-f-`, vì được dùng trong `$filter`) và `client` (văn bản ≤ 100 ký tự, ví dụ `LabChem 1.0.0 · desktop`). Schema riêng từng flow bên dưới (cho phép `null` ở trường tuỳ chọn). **Parse lỗi hoặc `requestId` sai định dạng vẫn phải để lại dấu vết**: ghi một dòng `REQUEST.END` (Rejected, `RequestId` trống, `Detail` = 500 ký tự đầu của payload) rồi Respond `state=Rejected`. |
| 0.5 | **Tra vai trò** (chỉ đọc) | Get items `LabRoles` — Filter `Title eq '<caller>' and IsActive eq 1`, Top 1 → `callerRole`, `callerName`. Không có → `callerRole = "None"`. |
| 0.6 | **Nhận yêu cầu (claim)** | Create item `LabRequests` `{Title = requestId, FlowName, ActorEmail = caller, State = InProgress}`. `Title` được đặt *duy nhất* nên nếu `requestId` đã tồn tại, SharePoint từ chối — nhánh *run after: has failed* đọc dòng đang có và xử lý theo bảng dưới. Đây là thay thế cho cách kiểm tra "đã có `Success` trong audit" cũ, vốn có khe hở: hai lần gọi song song đều qua được bước kiểm tra, và flow chết giữa chừng thì lần gửi lại tạo trùng toàn bộ. |
| 0.7 | **Ghi `REQUEST.START` — fail-closed** | Run `LAB-C02` ghi một dòng `REQUEST.START` (`Result=Started`, `Detail` = nguyên payload, kèm `ActorRole`). **Nếu C02 lỗi (sau 4 lần thử): cập nhật `LabRequests.State = Error`, Respond `state=Error` "Hệ thống tạm thời không ghi được nhật ký nên thao tác không được thực hiện. Không có dữ liệu nào bị thay đổi.", Terminate.** Không bao giờ làm tiếp khi chưa ghi được dấu vết. |
| 0.8 | **Kiểm tra vai trò** | `callerRole` không thuộc danh sách cho phép của flow → entry `ACCESS.DENIED` (`Rejected`, `Important`, lý do "Vai trò <callerRole> không được phép <action>") → **Khối kết thúc** (mục 2.4). Người không có vai trò cũng đi qua đây nên cũng được ghi lại. |
| 0.9 | **Scope `Try`** … **Scope `Catch`** | `Catch` chạy khi `Try` Failed/TimedOut: Khối kết thúc với `Result=Error`, `Detail` = `result('Try')` (lỗi kỹ thuật, chỉ nằm trong nhật ký) và `RunId = workflow()['run']['name']`; Respond `state=Error` "Có lỗi hệ thống, mã tham chiếu <RunId>. Chưa thử lại; hãy báo Admin kiểm tra". **Không trả chi tiết lỗi kỹ thuật cho client.** |

Xử lý khi `Create item LabRequests` thất bại vì trùng `requestId` (bước 0.6):

| Dòng `LabRequests` đang có | Việc làm |
|---|---|
| `State` = Done / Rejected / Error | Respond lại **nguyên văn** `ResultJson` đã lưu; ghi `REQUEST.DUPLICATE` (Info) qua C02; Terminate. Không chạy lại. |
| `State` = InProgress, tạo chưa quá `RequestStaleMinutes` phút | Respond `state=Busy` "Yêu cầu đang được xử lý, vui lòng đợi vài giây"; Terminate. App giữ nguyên `requestId` để hỏi lại. |
| `State` = InProgress, đã quá `RequestStaleMinutes` phút | Respond `state=Interrupted` "Yêu cầu trước đó bị gián đoạn. Báo Admin kiểm tra (mã <requestId>) trước khi thao tác lại"; ghi `REQUEST.DUPLICATE` (Warning). **Không tự chạy lại**: bản ghi tạo dở phải do người kiểm tra (`LAB-S03` liệt kê giúp). |

**Quy tắc `$filter`:** truy vấn SharePoint trong flow lọc bằng `ID` (số) hoặc mã đã kiểm định dạng. Chuỗi do người dùng nhập (tên, số lô, ghi chú, số biên bản) chỉ được **ghi** vào cột, không được nối vào `$filter`; nếu bắt buộc (ví dụ tìm theo `reportNo`), escape dấu nháy đơn bằng `replace(x, '''', '''''')`.

### 2.3 Hợp đồng phản hồi (Respond to a PowerApp or flow)

| Output | Kiểu | Ý nghĩa |
|---|---|---|
| `success` | Yes/No | Thành công hay không (`state = Done`) |
| `state` | Text | `Done` · `Rejected` (bị từ chối vì nghiệp vụ/quyền) · `Busy` (đang xử lý) · `Interrupted` (bị gián đoạn, cần Admin) · `Error` (lỗi hệ thống) |
| `message` | Text | Thông báo tiếng Việt hiển thị thẳng cho người dùng |
| `codes` | Text | Các mã tạo ra, phân tách bằng dấu phẩy (F01: mã chai, F02: mã dung dịch) |
| `ref` | Text | Mã tham chiếu để báo Admin (`RunId` rút gọn) |
| `lines` | Text (JSON) | Chỉ khi từ chối vì số liệu (không đủ lượng, hết hạn, trạng thái đã đổi): mảng `{code, requested, available, status, reason}` cho **từng dòng có vấn đề**, với `available` **tính từ sổ cái tại lúc lưu**. App dùng để cập nhật số trên màn hình mà không cần tải lại hay quét lại ([01 §5.5](01-Thiet-ke-tong-the.md)) |

Mọi nhánh từ chối nghiệp vụ trả `success=false` + `message` rõ nguyên nhân (ví dụ "IN-26-00041: không đủ lượng, còn 12,5 g") và **luôn ghi `LabAudit`**. Cách app xử lý từng `state` (khi nào sinh `requestId` mới) ở [04 §4.4](04-Power-Apps.md).

**Số lượng do app gửi chỉ là *lượng muốn dùng*.** Flow không bao giờ nhận "số còn lại" từ app để tin; số dư luôn tính lại từ sổ cái ở thời điểm lưu. Ngoại lệ duy nhất là `expectedQty` của `Adjust` (F04), dùng để *phát hiện* số dư đã đổi chứ không để tin.

### 2.4 Khối kết thúc (mọi lối ra: thành công, từ chối, lỗi)

1. Run `LAB-C02` với các entry theo từng đối tượng đã đổi (`auditRows`) **và** một dòng `REQUEST.END` (`Result` = Success/Rejected/Error; `Severity` = mức cao nhất trong các entry; `Detail` = `{success, state, message, codes, touched[], errors[]}` — `touched` liệt kê **mọi mã bị đổi, kể cả chai nguồn chỉ bị trừ số lượng**).
   *Nếu C02 lỗi sau 4 lần thử:* dữ liệu đã đổi mà dòng kết thúc chưa ghi được → gửi email cho Admin kèm `requestId` và kết quả (để vẫn có bằng chứng), rồi đi tiếp bước 2 (không hoàn tác). `LAB-S03` sẽ thấy yêu cầu thiếu dòng kết thúc và báo (mục 13).
2. Update item `LabRequests`: `State` = Done / Rejected / Error, `ResultJson` = đúng JSON sẽ trả cho app, `RunId`.
3. Nếu có entry `Severity = Critical`, kết quả Success và `AlertOnCritical = true`: **Send an email (V2)** ngay tới `AlertEmails` (hành động, đối tượng, người làm, vai trò, lý do, trước → sau, giờ, `requestId`, link app). Gửi email lỗi không làm hỏng yêu cầu.
4. Respond.

### 2.5 Nhật ký — quy tắc bắt buộc

Nhật ký không phải tính năng phụ: **thiếu dấu vết là lỗi nghiêm trọng**, kể cả khi dữ liệu đúng.

1. **Mọi đường ghi đi qua flow, mọi flow theo khối chuẩn.** App không `Patch`/`Collect` vào list `Lab*`; Admin cũng không có quyền ghi trực tiếp (xem [05 §2.2](05-Bao-mat-va-Kiem-thu.md)). Danh mục, vị trí, cấu hình và vai trò đổi qua `LAB-F05`.
2. **Ghi trước, làm sau (fail-closed).** `REQUEST.START` phải ghi được thì flow mới được đổi dữ liệu.
3. **Mọi yêu cầu có đủ cặp Started – kết thúc**, kể cả: payload hỏng, người không có vai trò, bị từ chối vì nghiệp vụ, gửi trùng, lỗi hệ thống.
4. **Mỗi đối tượng bị đổi trạng thái hoặc dữ liệu có một dòng riêng** (`EntityType`, `EntityID`, `EntityCode`) kèm `BeforeValue`/`AfterValue` (chỉ các trường đổi). Biến động **số lượng** được ghi ở `LabLedger` (mỗi dòng có `RequestId`, `ActorEmail`); hai nơi nối với nhau bằng `RequestId`, và `Detail.touched` của dòng kết thúc liệt kê mọi mã bị tác động.
5. **Lý do là cột riêng (`Reason`)**, bắt buộc với mọi hành động mức Critical và với `PREP.REVIEW` khi Rejected; sổ cái thêm `ReasonCode` (phân loại hao hụt) cho `Adjust`/`Dispose`.
6. **Danh tính do server xác định**: `ActorEmail` (từ header, không từ client), `ActorRole` và `ActorName` tra từ `LabRoles` tại thời điểm đó. Flow định kỳ ghi `system:LAB-S01`, `system:LAB-S02`, `system:LAB-S03`. Danh tính là **văn bản bất biến**, không phải cột Người: không đổi khi đổi tên/xoá tài khoản và luôn ghi được kể cả với tài khoản lạ.
7. **Thời gian là giờ máy chủ** (`Created` do SharePoint đặt). Ngày giờ người dùng nhập (`UsedDate`, `PrepDate`) là dữ liệu nghiệp vụ, không phải thời điểm ghi; chênh lệch lớn so với giờ máy chủ được ghi vào `Detail` (xem F03).
8. **Một `RequestId` xuyên suốt**: `LabRequests`, `LabAudit`, `LabLedger`, `LabLots`, `LabPreps`, `LabPrepItems`, `LabTestUsage` đều mang nó; `RunId` nối tới lịch sử chạy flow (chỉ giữ ~28 ngày nên không phải bằng chứng lâu dài).
9. **Chỉ thêm, không sửa, không xoá.** Tài khoản flow chỉ có quyền *Add* trên `LabAudit`, `LabLedger`, `LabPrepItems`, `LabTestUsage`. Nhật ký ghi sai thì thêm dòng đính chính, không sửa dòng cũ. Bị sửa/xoá ngoài app thì `LAB-S03` báo.
10. **Không ghi bí mật** (token, mật khẩu). Bật *Secure inputs/outputs* cho action của `LAB-C02` để dữ liệu nhật ký không lộ trong lịch sử chạy.
11. **Lỗi kỹ thuật chi tiết chỉ nằm ở `Detail`** của dòng kết thúc (Admin/Reviewer đọc), không trả về client.
12. **Có người rà soát.** Hằng ngày: email các sự kiện Critical và cảnh báo toàn vẹn (S01, S03). Hằng tháng: Reviewer rà soát nhật ký và ký xác nhận theo runbook ([05 §4](05-Bao-mat-va-Kiem-thu.md)). Nhật ký không ai đọc thì không có tác dụng kiểm soát.
13. **Phạm vi trung thực:** nhật ký ghi *thay đổi và quyết định*, không ghi từng lượt xem dữ liệu — người dùng có quyền đọc list nên có thể đọc trực tiếp ngoài app và app không chặn được. Ngoại lệ là các sự kiện app tự báo qua `LAB-F06` (độ tin cậy thấp hơn, đánh dấu `Source=ClientReport`). Truy cập site/file ở cấp SharePoint nhờ Purview audit ([05 §4](05-Bao-mat-va-Kiem-thu.md)).

### 2.6 Danh mục sự kiện (`LabAudit.Title`)

`LAB-C02` chỉ nhận các mã dưới đây; mã lạ bị ghi thành `AUDIT.INVALID_ENTRY` (Error) chứ không bị bỏ.

| Mã sự kiện | Phát sinh ở | Đối tượng | Mức | Lý do | Trước / sau |
|---|---|---|---|---|---|
| `REQUEST.START` / `REQUEST.END` | F01–F05 | Request | Info (END theo mức cao nhất) | — | START: nguyên payload; END: kết quả + `touched[]` |
| `REQUEST.DUPLICATE` | F01–F05 | Request | Info / Warning | — | — |
| `REQUEST.INTERRUPTED` | S03 | Request | Important | — | dấu vết đã tạo dở |
| `ACCESS.DENIED` | F01–F05 (không đủ vai trò), F06 (app báo) | System | Important | vai trò, hành động | — |
| `LOT.REGISTER` | F01 | Lot (mỗi chai) | Info | — | sau: danh mục, lượng, hạn, vị trí, trạng thái |
| `LOT.RELEASE` | F04 | Lot | Important | tuỳ chọn | `Status` |
| `LOT.ADJUST` | F04 | Lot | **Critical** | ✔ + mã lý do | `RemainingQty` |
| `LOT.DISPOSE` | F04 | Lot | **Critical** | ✔ + mã lý do | `RemainingQty`, `Status` |
| `LOT.VOID` | F04 | Lot | **Critical** | ✔ | `IsVoid`, `Status` |
| `LOT.EXPIRE` | S01 | Lot | Info | — | `Status` |
| `PREP.CREATE` | F02 | Prep | Important | — | sau: tên, lượng, hạn, **công thức** (mã + lượng từng thành phần) |
| `PREP.REVIEW` | F04 | Prep | Important | ✔ nếu Rejected | `ReviewStatus`, `ReviewedBy` |
| `PREP.ADJUST` / `PREP.DISPOSE` / `PREP.VOID` | F04 | Prep | **Critical** | ✔ + mã lý do | như Lot |
| `PREP.ROLLBACK` | F02 | Prep | Important | tự động | thành phần đã hoàn lại |
| `PREP.EXPIRE` | S01 | Prep | Info | — | `Status` |
| `USAGE.RECORD` | F03 | Lot / Prep (mỗi dòng) | Info | ✔ nếu `purpose=Other` | sau: số biên bản, lượng |
| `CATALOG.CREATE` | F05 | Catalog | Info | — | sau: toàn bộ trường |
| `CATALOG.UPDATE` / `CATALOG.DEACTIVATE` | F05 | Catalog | Important | ✔ | các trường đổi |
| `LOCATION.CREATE` / `LOCATION.UPDATE` / `LOCATION.DEACTIVATE` | F05 | Location | Info / Important | ✔ khi sửa, ngừng dùng | các trường đổi |
| `SETTING.SET` | F05 | Setting | **Critical** | ✔ | `Value` |
| `ROLE.SET` | F05 | Role | **Critical** | ✔ | `Role`, `IsActive` |
| `LABEL.PRINT` | F06 | Lot / Prep (mỗi mã) | Info; **Important nếu in lại** | — | — |
| `AUDIT.VIEW` | F06 | System | Info | — | bộ lọc đã dùng |
| `TRACE.VIEW` | F06 | Lot / Prep | Info | — | chỉ khi `LogTraceViews = true` |
| `STOCK.RACE_DETECTED` | F01–F04 (từ cảnh báo của C01) | Lot / Prep | Important | — | số dư dự kiến / thực |
| `STOCK.RECONCILE_FIX` | S02 | Lot / Prep | Important | — | cache cũ / mới |
| `RECORD.CODE_REPAIRED` | S02 | Lot / Prep | Important | — | `Title` cũ / mới |
| `JOB.RUN` | S01–S03 | System | Info / Warning | — | số liệu tổng kết |
| `INTEGRITY.ALERT` | S03 | System | **Critical** (hoặc Important) | — | phát hiện cụ thể |
| `AUDIT.INVALID_ENTRY` | C02 | System | Important | — | entry bị loại |

### 2.7 Một dòng nhật ký trông thế nào

Ví dụ Admin điều chỉnh tồn một chai (`LOT.ADJUST`):

| Cột | Giá trị |
|---|---|
| `Title` | `LOT.ADJUST` |
| `EntityType` · `EntityID` · `EntityCode` | `Lot` · `42` · `IN-26-00042` |
| `Result` · `Severity` | `Success` · `Critical` |
| `Reason` | Kiểm đếm lại: còn 180 mL, không phải 200 mL |
| `BeforeValue` | `{"RemainingQty":200,"Status":"InUse"}` |
| `AfterValue` | `{"RemainingQty":180,"Status":"InUse"}` |
| `Detail` | `{"ledgerDelta":-20,"reasonCode":"CountCorrection"}` |
| `ActorEmail` · `ActorName` · `ActorRole` | `an.nguyen@contoso.com` · `Nguyễn An` · `Admin` |
| `Source` · `FlowName` | `App` · `LAB-F04 AdminAction` |
| `RequestId` · `RunId` | `3f2b…` · `08584…` |
| `ClientInfo` | `LabChem 1.0.0 · desktop` |
| `Created` (SharePoint đặt) | `2026-10-24 09:31:07` |

**Dựng lại đời sống một chai** (câu hỏi điển hình của kiểm toán viên): lọc `LabAudit` theo `EntityCode = IN-26-00042` (ai đăng ký, ai release, ai điều chỉnh/huỷ, vì sao) + `LabLedger` theo `ItemID` (mọi biến động số lượng, người làm, `RequestId`) + `LabPrepItems`/`LabTestUsage` (dùng ở đâu). Từ bất kỳ `RequestId` nào tra ngược được toàn bộ những gì yêu cầu đó đã tạo ra.

### 2.8 Ghi chú vận hành
- **Lịch sử chạy của flow chỉ lưu khoảng 28 ngày** → bằng chứng kiểm toán lâu dài nằm ở `LabAudit` + `LabLedger` + version history, không nằm ở run history.
- Instant flow không có *Concurrency control* nên hai lần gọi có thể chạy song song; thiết kế xử lý bằng `LabRequests` (cùng `RequestId`), cơ chế kiểm tra lại sau khi ghi trong `LAB-C01` (khác `RequestId`, cùng chai) và đối soát `LAB-S02` (mục 4 và 9).
- Power Apps chờ phản hồi flow tối đa khoảng 2 phút. Ghi nhật ký thêm khoảng 4 lần gọi action tối thiểu mỗi yêu cầu (claim, Started, kết thúc, cập nhật `LabRequests`) — dự kiến cộng vài giây, **chưa đo**; giữ mỗi flow dưới ~30–45 giây ở điều kiện thường (F01 dùng song song 5 luồng). Nhiều entry gửi trong **một** lần gọi C02 để giảm chi phí.
- **Biến mảng trong vòng lặp song song không an toàn** (các lần ghi có thể đè nhau): không dùng *Append to array variable* trong vòng có Concurrency > 1. Sau vòng lặp, đọc lại bản ghi theo `RequestId` rồi dùng *Select* (xem F01 bước 6b).
- Hạn mức API / số action mỗi ngày phụ thuộc giấy phép của tenant và tính theo tài khoản dịch vụ — cần IT xác nhận. Quy mô lab (vài trăm thao tác/ngày, ~10–40 action/thao tác kể cả nhật ký) vẫn nhỏ so với hạn mức thông thường, nhưng `LAB-S02`/`LAB-S03` nên chạy gia tăng.

---

## 3. LAB-F01 RegisterIncoming

**Vai trò được phép:** Admin, Analyst.

**Payload**
```json
{
  "requestId": "guid",
  "client": "LabChem 1.0.0 · desktop",
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

1. Khối chuẩn 0.1–0.9 (vai trò: Admin, Analyst).
2. Đọc `LabSettings`: `MaxBottlesPerReceipt`, `RequireIncomingRelease`, `ReportUrlAllowedHosts` (nếu dùng cho `coaLink`).
3. Get item `LabCatalog` theo `catalogId`.
4. **Kiểm tra** — gom lỗi vào mảng `errors`, nếu có lỗi thì **Khối kết thúc** với `Rejected` (chưa tạo gì):
   - danh mục tồn tại và `IsActive`;
   - `unit` = `BaseUnit` của danh mục;
   - `qty` > 0; `1 ≤ bottleCount ≤ MaxBottlesPerReceipt`;
   - `receivedDate` không ở tương lai; `mfgDate ≤ receivedDate`; `expiryDate > receivedDate` (không nhận hoá chất đã hết hạn);
   - `coaLink` rỗng hoặc bắt đầu `https://` (và đúng host cho phép nếu có cấu hình);
   - `locationId` rỗng hoặc tồn tại và `IsActive`.
5. Biến `initialStatus` = `Quarantine` nếu `RequireIncomingRelease` = `true`, ngược lại `Available`.
6. **Apply to each** trên `range(0, bottleCount)` — *Concurrency control = 5* (mỗi vòng độc lập nhờ mã sinh từ `ID`). **Không dùng biến mảng trong vòng này:**
   1. **Create item** `LabLots`: `Title = guid()`, các cột snapshot (`ChemName`, `CasNumber` từ danh mục; `LocationName` từ vị trí), `InitialQty = RemainingQty = qty`, `Status = initialStatus`, `RegisteredBy = caller`, **`RequestId`**.
   2. **Update item** `Title = concat('IN-', formatDateTime(outputs('nowLocal'),'yy'), '-', formatNumber(outputs('Create_Lot')?['body/ID'], '00000'))`.
   3. **Create item** `LabLedger`: `ItemType=Lot`, `ItemID=ID`, `TxnType=Receive`, `QtyDelta=qty`, `BalanceAfter=qty`, `Actor=caller`, **`ActorEmail=caller`, `RequestId`**.
   (Giao dịch `Receive` ghi trực tiếp, không qua `LAB-C01` vì chưa có số dư trước đó.)
6b. **Đọc lại những gì vừa tạo:** Get items `LabLots` — Filter `RequestId eq '<requestId>'` → *Select* ra `codes` (danh sách `Title`) và `auditRows`: mỗi chai một entry `LOT.REGISTER` (`EntityID`, `EntityCode`, `AfterValue = {catalogId, mfgLot, qty, unit, expiryDate, locationId, status}`). Cách này an toàn với vòng song song và cũng cho thấy nếu có chai nào tạo dở.
7. **Cập nhật tồn cao nhất (`PeakQty`):** Get items `LabLots` — Filter `CatalogID eq <id> and (Status eq 'Available' or Status eq 'InUse' or Status eq 'Quarantine')`, cộng `RemainingQty` → `total`. Nếu `total` lớn hơn `PeakQty` của danh mục (hoặc `PeakQty` trống) → Update item `LabCatalog` đặt `PeakQty = total`. Đây là mốc 100% mặc định cho cảnh báo sắp hết khi Admin chưa đặt `ParLevelQty`. (Đổi `PeakQty` là thay đổi tự động, ghi trong `Detail` của dòng kết thúc.)
8. **Khối kết thúc** (Success): các entry `LOT.REGISTER` ở 6b + `REQUEST.END` (`touched` = các mã chai).
9. **Respond**: `success=true`, `state=Done`, `message="Đã tạo @{length(body('Select_Codes'))} chai"`, `codes=join(sort(body('Select_Codes')),',')`.

**Lỗi dở dang:** nếu lỗi xảy ra giữa bước 6.1 và 6.3 thì có thể tồn tại chai có `Title` dạng GUID hoặc thiếu dòng sổ cái. Dòng kết thúc `Error` đã được ghi bởi `Catch`; `LAB-S03` liệt kê mọi bản ghi mang `RequestId` đó, `LAB-S02` quét và sửa/cảnh báo các trường hợp này (mục 9). **Gửi lại cùng `RequestId` không tạo thêm chai** (trả `Error` đã lưu); Admin kiểm tra rồi mới cho nhập lại.

---

## 4. LAB-C01 PostTransaction (child flow) — "cổng ghi sổ cái"

Mọi biến động `PrepUse`, `TestUse`, `PrepCreate`, `Adjust`, `Dispose`, `Reversal` đi qua flow này. Đặt toàn bộ logic số dư/trạng thái ở **một chỗ**.

**Trigger:** *Manually trigger a flow* — inputs: `itemType` (`Lot`|`Prep`), `itemId`, `txnType`, `qtyDelta` (số, âm = xuất), `unit`, `refType`, `refCode`, `reason`, `reasonCode`, `actor` (email), `requestId`.

**Output:** `ok` (Yes/No), `balanceBefore`, `balance` (số), `status` (text), `message`, `warnings` (text, ví dụ `race`).

**Các bước**

1. Get item cha (`LabLots` hoặc `LabPreps` theo `itemType`): `RemainingQty`, `InitialQty`/`FinalQty`, `Unit`, `Status`, `ExpiryDate`, `Title`.
2. Kiểm tra `unit` = `Unit` của cha (BR-04), nếu sai → `ok=false`.
3. **Tính số dư từ sổ cái:** Get items `LabLedger` — Filter `ItemType eq '<t>' and ItemID eq <id>`, Top 5000 (bật pagination). Initialize `sum` (Float) = 0 → Apply to each (tuần tự) → *Increment variable* `sum` bằng `items('…')?['QtyDelta']`. `balanceBefore = sum`.
4. `newBalance = float(formatNumber(add(variables('sum'), qtyDelta), '0.0000'))`.
5. Nếu `newBalance < -0.00005` → trả `ok=false`, `message="Không đủ lượng: còn <sum> <unit>"`, `balance = sum` (số dư thực từ sổ cái, để flow cha đưa vào `lines`); **không ghi gì**.
6. **Create item** `LabLedger`: `Title=<mã cha>`, `QtyDelta`, `BalanceAfter=newBalance`, `RefType`, `RefCode`, `Reason`, `ReasonCode`, `Actor`, **`ActorEmail`, `RequestId`**.
7. **Kiểm tra lại sau khi ghi** (chống đua): tính lại tổng `sum2` từ sổ cái như bước 3.
   - `sum2 = newBalance`: bình thường.
   - `sum2 ≠ newBalance` và `sum2 ≥ 0`: có giao dịch khác chen vào. **Không sửa dòng sổ cái vừa ghi** (sổ cái chỉ thêm — `BalanceAfter` chỉ là số dư tham khảo tại thời điểm ghi). Đặt `newBalance = sum2` để cập nhật cache cha và trả `warnings = "race"`; flow cha ghi `STOCK.RACE_DETECTED`.
   - `sum2 < -0.00005`: ghi ngay một dòng `Reversal` bù (+`qtyDelta`, lý do "Xung đột đồng thời", cùng `RequestId`), gửi cảnh báo cho Admin, trả `ok=false`, `message="Xung đột đồng thời, giao dịch đã bị huỷ — thử lại"`, `warnings = "race"`.
8. **Update item cha:**
   - `RemainingQty = newBalance`
   - `Status`: giữ nguyên nếu đang `Disposed` hoặc `Quarantine`; nếu `txnType = Dispose` → `Disposed`; nếu `newBalance ≤ 0.00005` → `Empty`; nếu `ExpiryDate < hôm nay` → `Expired`; nếu `newBalance < InitialQty` (hoặc `FinalQty`) → `InUse`; ngược lại `Available`.
   - Với `Lot`: nếu `OpenedDate` trống và `txnType ∈ {PrepUse, TestUse}` → `OpenedDate = hôm nay`.
9. Respond `ok=true`, `balanceBefore`, `balance`, `status`, `warnings`.

> **Về nhật ký:** `RemainingQty` và `Status` của chai/dung dịch là **bản cache suy ra từ sổ cái** nên đổi tự động không cần dòng `LabAudit` riêng (mỗi lần đổi đã có dòng sổ cái mang `RequestId`, `ActorEmail`). Các chuyển trạng thái do **con người quyết định** (Release, Review, Void, Dispose…) thì luôn có dòng `LabAudit` — xem F04.

> **Giới hạn đã biết:** vì instant flow không có concurrency control, nếu hai người cùng trừ **cùng một chai** trong khoảng vài giây, bước 7 phát hiện và bù lại; cửa sổ đua còn lại cực nhỏ và được `LAB-S02` quét hằng đêm. Với quy mô phòng lab, rủi ro này chấp nhận được; nếu cần tuyệt đối, chuyển sang khoá bản ghi bằng cột `LockedBy` hoặc dùng Dataverse.

---

## 5. LAB-F02 CreatePreparation

**Vai trò được phép:** Admin, Analyst.

**Payload**
```json
{
  "requestId": "guid",
  "client": "LabChem 1.0.0 · desktop",
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

1. Khối chuẩn 0.1–0.9 (Admin, Analyst).
2. **Kiểm tra phần đầu:** `prepName` không rỗng; `finalQty > 0`; `prepDate` không ở tương lai và không quá cũ hơn 7 ngày (Admin được bỏ qua giới hạn này); `expiryDate > prepDate`; `1 ≤ items ≤ 30`; không có hai dòng trùng (`sourceType`+`sourceId`) — so `length(union(...))` với `length(items)`; mọi `qty > 0`. Nếu `prepDate` lùi quá 24 giờ so với giờ máy chủ: ghi `backdatedDays` vào `Detail` của dòng kết thúc.
3. **Với từng dòng thành phần** (Apply to each, tuần tự): Get item nguồn theo `sourceType`, kiểm tra
   - BR-03: `Status ∈ {Available, InUse}`, `ExpiryDate ≥ prepDate`, `IsVoid = false`; nếu nguồn là `Prep` thì `ReviewStatus ≠ Rejected`;
   - `qty ≤ RemainingQty` (kiểm tra sơ bộ trên cache — chạy cho **mọi dòng trước khi trừ bất cứ dòng nào**, nên thường bị từ chối trước khi đụng đến sổ cái);
   - ghi vào mảng `resolved`: id, mã, tên, số lô NSX, đơn vị, `qty`, `role`, `ExpiryDate`.
   Lỗi nào cũng thêm vào mảng `errors` dạng `"<mã>: <lý do>"`.
4. Nếu `errors` không rỗng → **Khối kết thúc** `Rejected` (`Detail.errors`) → Respond `success=false`, `state=Rejected`, `message=join(errors,'; ')`, và **`lines`**: với mỗi dòng lỗi, `available` là số dư **tính lại từ sổ cái** (Σ `QtyDelta`) chứ không lấy từ cache, để người dùng thấy đúng con số hiện tại.
5. Nếu `EnforcePrepExpiryLimit = true` và `expiryDate > hạn sớm nhất của resolved` → Rejected với thông báo nêu mã thành phần giới hạn hạn dùng.
6. **Create item** `LabPreps` (`Title=guid()`, `RemainingQty=0`, `Status=Available`, `ReviewStatus=Pending`, `PreparedBy=caller`, `RequestId`, snapshot `LocationName`) → **Update** `Title = 'PC-' & yy & '-' & formatNumber(ID,'00000')`.
7. **Với từng dòng `resolved`** (tuần tự, biến `failed=false`):
   1. Create item `LabPrepItems` (`Title=PrepCode`, `PrepID`, nguồn + snapshot, `RequestId`).
   2. Run child flow **LAB-C01** (`PrepUse`, `-qty`, `RefType=Prep`, `RefCode=PrepCode`, `actor`, `requestId`). Nếu C01 trả `warnings = race` → thêm entry `STOCK.RACE_DETECTED`.
   3. Nếu `ok=false` (người khác vừa chen vào) → `failed=true`, lưu thông báo và `balance` do C01 trả về (đưa vào `lines`), **thoát vòng lặp** (các dòng sau bỏ qua).
8. **Bước 9 cũng phải nằm trong cơ chế rollback.** Nếu `failed`, **hoặc** bước 9 (`PrepCreate`) lỗi: **rollback** — với mỗi dòng đã trừ thành công gọi `LAB-C01` loại `Reversal` (+`qty`, lý do "Rollback tạo <PrepCode>"); cập nhật dung dịch `IsVoid=true`, `Status=Disposed`, `VoidReason`; entry `PREP.ROLLBACK` (liệt kê thành phần đã hoàn lại); **Khối kết thúc** `Rejected`/`Error` → Respond `success=false`.
   *(Thiết kế trước chỉ rollback khi lỗi ở vòng thành phần: nếu `PrepCreate` lỗi sau khi đã trừ hết thành phần thì nguyên liệu mất mà dung dịch rỗng. Nếu chính rollback lại lỗi, `Catch` ghi `Error`, và `LAB-S02` phát hiện dung dịch có `PrepUse` mà tổng sổ cái bằng 0.)*
9. Nếu không lỗi: Run `LAB-C01` (`PrepCreate`, `+finalQty` trên chính dung dịch) → số dư dung dịch = `finalQty`. Lỗi → bước 8.
10. **Khối kết thúc** (Success): entry `PREP.CREATE` (`EntityID`, `EntityCode`, `AfterValue = {prepName, finalQty, unit, expiryDate, locationId, items:[{code, qty, unit, role}]}` — chính là công thức đã dùng) + `REQUEST.END` (`touched` = mã dung dịch **và mã mọi chai/dung dịch nguồn**) → Respond `success=true`, `codes=<PrepCode>`.

---

## 6. LAB-F03 RecordUsage

**Vai trò được phép:** Admin, Analyst. Dùng để *gắn hoá chất vào biên bản thử nghiệm* (yêu cầu truy xuất) và ghi nhận dùng cho mục đích khác.

**Payload**
```json
{
  "requestId": "guid",
  "client": "LabChem 1.0.0 · desktop",
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

1. Khối chuẩn 0.1–0.9 (Admin, Analyst).
2. **Kiểm tra:** `purpose ∈ {Test, Other}`; `purpose=Test` ⇒ `reportNo` bắt buộc (≤ 100 ký tự); `purpose=Other` ⇒ `note` bắt buộc (lý do); `reportUrl` rỗng hoặc bắt đầu `https://` và (nếu `ReportUrlAllowedHosts` có cấu hình) hậu tố host nằm trong danh sách — chặn `javascript:`/`data:` và liên kết ra ngoài; `usedDate` không ở tương lai; `1 ≤ lines ≤ 20`, không trùng dòng, `qty > 0`. Nếu `usedDate` lùi quá 24 giờ so với giờ máy chủ: ghi `backdatedHours` vào `Detail` (ghi bù được phép nhưng phải thấy được khi kiểm toán).
3. **Với từng dòng:** Get đối tượng, kiểm tra BR-03, BR-04, `qty ≤ RemainingQty`. Gom lỗi như F02; có lỗi → Rejected, **chưa ghi gì**, trả `lines` với số dư tính lại từ sổ cái.
4. **Với từng dòng** (tuần tự): Run `LAB-C01` (`TestUse`, `-qty`, `RefType = Report` nếu `Test` ngược lại `Manual`, `RefCode = reportNo`, `Reason = note`, `actor`, `requestId`). Nếu có dòng `ok=false` → rollback các dòng trước bằng `Reversal` → Rejected.
5. Chỉ khi mọi dòng đã trừ thành công và `purpose=Test`: Create item `LabTestUsage` cho từng dòng (`Title=reportNo`, `ReportUrl`, `TestName`, `SampleCode`, `ItemType/ItemID/ItemCode/ItemName`, `QtyUsed`, `Unit`, `UsedDate`, `Analyst=caller`, `RequestId`).
   Tạo `LabTestUsage` **sau** khi trừ tồn thành công vì list này không cho xoá; nếu bước này lỗi, `LAB-S02` phát hiện dòng sổ cái `RefType=Report` thiếu `LabTestUsage` và cảnh báo.
6. **Khối kết thúc** (Success): mỗi dòng một entry `USAGE.RECORD` (`EntityType`/`EntityCode` của hoá chất, `AfterValue = {purpose, reportNo, qty, unit}`) + `REQUEST.END` → Respond `success=true`, `message="Đã ghi nhận <n> dòng cho biên bản <reportNo>"`.

---

## 7. LAB-F04 AdminAction

**Payload:** `{ requestId, client, action, itemType, itemId, newQty, expectedQty, decision, reason, reasonCode }` — `expectedQty` là số dư người dùng đã thấy khi mở hộp thoại `Adjust`.

| `action` | Vai trò | Điều kiện | Việc làm | Sự kiện nhật ký |
|---|---|---|---|---|
| `Adjust` | Admin | `reason` ≥ 10 ký tự; `reasonCode` bắt buộc; `newQty ≥ 0`; khác số dư hiện tại; **`expectedQty` phải bằng số dư hiện tại tính từ sổ cái** — nếu đã đổi (ví dụ 200 → 170 vì có người vừa dùng) thì từ chối "Số dư vừa đổi (200 → 170) trong lúc đang nhập, hãy kiểm đếm lại", không đổi gì | `LAB-C01` `Adjust` với `qtyDelta = newQty − số dư` | `LOT.ADJUST` / `PREP.ADJUST` — **Critical**; trước/sau = `RemainingQty`, `Status` |
| `Dispose` | Admin | `reason` + `reasonCode` bắt buộc; còn tồn | `LAB-C01` `Dispose` với `-số dư` → `Status=Disposed` | `LOT.DISPOSE` / `PREP.DISPOSE` — **Critical** |
| `Void` | Admin | `reason` bắt buộc; **không** có hậu duệ: Get `LabPrepItems` (`SourceType`,`SourceID`) và `LabTestUsage` (`ItemType`,`ItemID`) đều rỗng | `LAB-C01` `Reversal` về 0; đặt `IsVoid=true`, `Status=Disposed`, `VoidReason`. Nếu có hậu duệ → từ chối, hướng dẫn dùng `Dispose` | `LOT.VOID` / `PREP.VOID` — **Critical** |
| `Release` | Reviewer, Admin | `itemType=Lot` và `Status=Quarantine` | `Status=Available` | `LOT.RELEASE` — Important; trước/sau = `Status` |
| `Review` | Reviewer, Admin | `itemType=Prep`; `decision ∈ {Approved, Rejected}`; `ReviewedBy ≠ PreparedBy` (BR-08); `Rejected` ⇒ `reason` bắt buộc | `ReviewStatus`, `ReviewedBy=caller`, `ReviewedOn=now` | `PREP.REVIEW` — Important; trước/sau = `ReviewStatus`, `ReviewedBy` |

Mọi `action` đều qua khối chuẩn nên **ghi `LabAudit` kèm `reason`, kể cả khi bị từ chối** (vai trò sai, thiếu lý do, `Void` có hậu duệ, người duyệt trùng người pha…). Sự kiện mức **Critical** gửi email ngay (mục 2.4 bước 3).

---

## 8. LAB-S01 DailyExpiryStock (Recurrence 07:00 giờ Việt Nam)

1. Ghi `JOB.RUN` (Started; `ActorEmail = system:LAB-S01`, `Source = Scheduled`). Đọc `ExpiryWarnDays` (mặc định 30), `AlertEmails`.
2. **Đánh dấu hết hạn:** Get `LabLots` và `LabPreps` — Filter `(Status eq 'Available' or Status eq 'InUse') and ExpiryDate lt '<hôm nay>'` → Update `Status=Expired`. **Mỗi đối tượng một entry** `LOT.EXPIRE` / `PREP.EXPIRE` (trước/sau = `Status`) gom bằng *Select* và gửi C02 (tối đa 100 entry/lần gọi) — không chỉ một dòng tổng kết, để biết chính xác chai nào đổi trạng thái lúc nào.
3. **Sắp hết hạn:** cùng bộ lọc với `ExpiryDate ge '<hôm nay>' and ExpiryDate le '<hôm nay + N>'` → *Create HTML table* (mã, tên, số lô, hạn dùng, còn lại, vị trí).
4. **Sắp hết — cần mua thêm (BR-13):** đọc `DefaultLowStockPct` (mặc định 20). Get `LabCatalog` — `IsActive eq 1`. Với mỗi hoá chất:
   - `ref` = `ParLevelQty` nếu > 0, ngược lại `PeakQty`; nếu `ref ≤ 0` thì bỏ qua (chưa có mốc để so);
   - `pct` = `LowStockPct` nếu > 0, ngược lại `DefaultLowStockPct`;
   - Get `LabLots` — `CatalogID eq <id> and (Status eq 'Available' or Status eq 'InUse' or Status eq 'Quarantine')`, cộng `RemainingQty` → `total`;
   - nếu `total < ref × pct / 100` (kể cả `total = 0`) → thêm dòng vào bảng "Cần mua thêm": tên, còn `total` / chuẩn `ref` (`total/ref` %), ngưỡng `pct`%.
4b. **Chai đang dùng sắp hết:** Get `LabLots` — `Status eq 'InUse'`; với mỗi chai lấy `pct` của hoá chất (như trên), chọn chai có `RemainingQty × 100 < InitialQty × pct` bằng *Filter array* (OData không so sánh hai cột với nhau được) → bảng "Chai sắp hết".
5. **Báo cáo kiểm soát (24 giờ qua):** Get `LabAudit` — `Severity eq 'Critical' and Created ge '<hôm qua>'` → bảng "Sự kiện mức Critical" (giờ, hành động, đối tượng, người làm, lý do); thêm số dòng `Rejected` và `Error` và các cảnh báo `INTEGRITY.ALERT` từ S03.
6. **Luôn gửi** **Send an email (V2)** tới `AlertEmails` (HTML gọn: bảng sắp hết hạn, **cần mua thêm**, chai sắp hết, **sự kiện Critical**, + link mở app). Ngày không có gì thì gửi một dòng "Không có mục nào cần xử lý" — **việc email hằng ngày đến đều đặn cũng là tín hiệu**: không thấy email nghĩa là S01/tài khoản dịch vụ có vấn đề, Reviewer phải hỏi ngay.
7. Ghi `JOB.RUN` kết thúc (số chai/dung dịch đã đánh dấu hết hạn, số mục cảnh báo). Phase 2: thêm bài đăng Teams; ghi snapshot KPI vào `LabSettings` khi dữ liệu vượt ngưỡng delegation.

## 9. LAB-S02 Reconcile (Recurrence 02:00)

Chạy **gia tăng mỗi đêm**, **toàn bộ mỗi Chủ nhật**. Ghi `JOB.RUN` (Started/kết thúc), `ActorEmail = system:LAB-S02`.

1. Tập cần kiểm: gia tăng = các `(ItemType, ItemID)` có dòng `LabLedger` với `Created ge now−2 ngày` (loại trùng); toàn bộ = mọi `LabLots`/`LabPreps` chưa `Disposed`.
2. Với từng đối tượng: tính Σ `QtyDelta`; so với `RemainingQty`. Lệch > 0.00005 → sửa cache bằng giá trị từ sổ cái, ghi `STOCK.RECONCILE_FIX` (Important; trước/sau), gom vào email cho Admin. Sổ cái luôn thắng. *(Cache bị đổi ngoài flow là dấu hiệu cần điều tra: ai sửa? — xem `Modified By` của dòng trước khi sửa lại.)*
3. **Bản ghi dở dang:** `Title` còn là GUID (không khớp `IN-yy-nnnnn` / `PC-yy-nnnnn`) → sinh lại mã từ `ID`, ghi `RECORD.CODE_REPAIRED` và cảnh báo; chai thiếu dòng `Receive`; dòng sổ cái `RefType=Report` không có `LabTestUsage` tương ứng; **dung dịch có dòng `PrepUse` nhưng tổng sổ cái = 0 và chưa Void** (nghi `PrepCreate` hỏng) → cảnh báo Admin xử lý.
4. Tổng kết một dòng `JOB.RUN` (số đối tượng đã kiểm, số lệch).

## 10. LAB-C02 WriteAudit (child flow) — "cổng ghi nhật ký"

Mọi dòng `LabAudit` đều do flow này ghi, để định dạng đồng nhất và có một chỗ duy nhất để sửa/kiểm.

**Trigger:** *Manually trigger a flow* — inputs: `common` (JSON: `requestId`, `actorEmail`, `actorName`, `actorRole`, `source`, `flowName`, `runId`, `clientInfo`) và `entries` (JSON mảng; mỗi phần tử `{action, entityType, entityId, entityCode, result, severity, reason, before, after, detail}`).

**Output:** `ok` (Yes/No), `count`, `failed`.

**Các bước**

1. Parse JSON `common` và `entries`.
2. **Kiểm tra:** `actorEmail` không rỗng; số entry ≤ 200; `action` thuộc danh mục ở mục 2.6; `result`, `severity`, `entityType`, `source` thuộc danh sách cột Choice; Critical thì `reason` không rỗng (trừ `INTEGRITY.ALERT`, `JOB.RUN`). Entry sai **không bị bỏ**: thay bằng `AUDIT.INVALID_ENTRY` (Error, Important) với `Detail` = 500 ký tự đầu của entry gốc.
3. **Apply to each** (Concurrency 5; *Retry policy* của action Create item: Exponential, 4 lần): Create item `LabAudit` — `Title=action`, các cột theo entry và `common`; cắt chuỗi cho vừa cột Text (255).
4. Output `ok = (failed = 0)`. Nếu còn dòng ghi lỗi sau khi thử lại → `ok=false` (flow cha áp dụng fail-closed ở START hoặc gửi email Admin ở bước kết thúc).

Bật *Secure inputs/outputs* cho các action của flow này.

## 11. LAB-F05 AdminData

**Vai trò được phép:** Admin. Đây là **đường duy nhất** để đổi dữ liệu gốc; màn Quản trị không `Patch` trực tiếp (Admin chỉ có quyền đọc — [05 §2.2](05-Bao-mat-va-Kiem-thu.md)).

**Payload:** `{ requestId, client, action, id, fields, key, value, email, role, isActive, displayName, reason }` (chỉ dùng các trường thuộc `action`).

| `action` | Dữ liệu | Quy tắc | Sự kiện |
|---|---|---|---|
| `CatalogSave` | `id` (0 = tạo mới), `fields`: tên, CAS, loại, cấp độ, đơn vị gốc, nguy hiểm GHS, bảo quản, `parLevelQty`, `lowStockPct`, link SDS, `isActive` | tên không rỗng; `baseUnit ∈ {g, mL, pcs}`; `lowStockPct` trống hoặc 1–99; `parLevelQty` trống hoặc ≥ 0; link SDS `https://`; **không đổi `baseUnit` nếu đã có chai thuộc danh mục** (Get `LabLots` `CatalogID eq <id>`, Top 1) — nếu đổi, tổng tồn cộng lẫn đơn vị và cảnh báo % sai; sửa/ngừng dùng cần `reason` ≥ 10 ký tự; trùng tên + CAS chỉ cảnh báo | `CATALOG.CREATE` (Info) · `CATALOG.UPDATE` / `CATALOG.DEACTIVATE` (Important) |
| `PeakReset` | `id`, `reason` | đặt `PeakQty` = tổng tồn hiện tại ("Đặt lại về tồn hiện tại") | `CATALOG.UPDATE` |
| `LocationSave` | `id`, tên, phòng, ghi chú, `isActive` | tên duy nhất (SharePoint ép); ngừng dùng thì `Detail` ghi số chai/dung dịch đang đặt ở đó (cảnh báo, không chặn); sửa/ngừng cần `reason` | `LOCATION.*` |
| `SettingSet` | `key`, `value`, `reason` | `key` phải là khoá có sẵn (không tạo khoá mới, không đụng khoá bắt đầu bằng `State_`); kiểm giá trị theo khoá: số nguyên trong khoảng (`DefaultLowStockPct` 1–99, `ExpiryWarnDays` 1–365, `MaxBottlesPerReceipt` 1–100, `RequestStaleMinutes` 5–240), `true`/`false`, `LabelBarcode ∈ {Code39, None}`, `QRMode ∈ {CodeOnly, DeepLink}`, danh sách email, danh sách host (bắt đầu bằng dấu chấm), URL `https://` | `SETTING.SET` — **Critical** |
| `RoleSet` | `email`, `role`, `isActive`, `displayName`, `reason` | email hợp lệ, chuyển chữ thường; **không đổi/ngừng vai trò của chính mình**; **không để lại 0 Admin đang hiệu lực** (đếm sau thay đổi); `reason` bắt buộc; thông báo nhắc "nhớ thêm/bớt người này trong nhóm SharePoint LabChem *" (R-04; S03 kiểm lệch) | `ROLE.SET` — **Critical** |

**Các bước:** (1) khối chuẩn 0.1–0.9 (Admin); (2) kiểm tra theo `action`, gom `errors`; (3) Get bản ghi hiện tại → `BeforeValue` (chỉ trường sẽ đổi); (4) Create/Update item; (5) `AfterValue`; (6) Khối kết thúc (entry + `REQUEST.END`; Critical gửi email ngay).

> Admin cấp quyền Admin cho người khác hoặc nới một cấu hình kiểm soát (ví dụ tắt `RequireIncomingRelease`) là hành động nhạy cảm nhất của hệ thống. Vì vậy: luôn Critical, email ngay, và `AlertEmails` nên gồm ít nhất một người **không** phải người vừa thao tác.

## 12. LAB-F06 LogEvent

**Vai trò được phép:** mọi người dùng (kể cả không có vai trò, riêng sự kiện `ACCESS.DENIED`). **Payload:** `{ requestId, client, event, entityType, codes, note }` — `codes` là văn bản, các mã cách nhau bằng dấu phẩy.

Chỉ ghi các sự kiện **do app báo** (`Source = ClientReport`, `Detail.clientReported = true`). Không có cặp Started–kết thúc: các dòng sự kiện chính là bản ghi; vẫn *claim* `LabRequests` để chống ghi trùng.

| `event` | Ai | Quy tắc |
|---|---|---|
| `LABEL.PRINT` | Admin, Analyst | tối đa 50 mã trong `codes`; mỗi mã đúng mẫu `^(IN|PC)-\d{2}-\d{5}$` và tồn tại; mỗi mã một dòng. Nếu đã có `LABEL.PRINT` trước đó cho mã (Get `LabAudit`, `EntityCode eq <mã>`, `Title eq 'LABEL.PRINT'`, Top 1) → `Detail.reprint = true`, mức **Important** (in lại là điểm kiểm soát: hai nhãn cùng mã dán lên hai chai). Lần đầu: Info. |
| `AUDIT.VIEW` | Admin, Reviewer | một dòng mỗi lần mở màn Nhật ký; `Detail` ghi bộ lọc đã dùng |
| `TRACE.VIEW` | mọi vai trò | chỉ ghi khi `LogTraceViews = true`; ngược lại trả OK và bỏ qua |
| `ACCESS.DENIED` | bất kỳ ai, kể cả `None` | người mở app mà không có vai trò; tối đa **1 dòng/giờ/người** (Get `LabAudit` `ActorEmail`, `Title`, `Created ge now−1h`; đã có thì bỏ qua) để không bị làm ngập |

**Giới hạn phải nói rõ:** sự kiện do client báo có thể bị bỏ qua (người dùng không gọi flow). `Print()` không cho app biết giấy có thật sự được in; ta ghi **"người dùng đã bấm in"**, không phải "đã in". Việc đọc dữ liệu trực tiếp trên SharePoint không ghi được (mục 2.5, nguyên tắc 13).

## 13. LAB-S03 IntegrityWatch (Recurrence 03:30)

Giám sát **bản thân nhật ký và sổ cái**: phát hiện việc không để lại dấu vết hoặc bị can thiệp ngoài app. Ghi `JOB.RUN` (Started/kết thúc), `ActorEmail = system:LAB-S03`. Trạng thái giữa các lần chạy lưu ở `LabSettings` với khoá `State_*` (F05 không cho sửa tay).

1. **Cặp Started–kết thúc.** Với mọi `LabRequests` tạo trong 24 giờ qua, `LabAudit` phải có đúng một `REQUEST.START` và một `REQUEST.END` mang `RequestId` đó.
   - Thiếu `START` → `INTEGRITY.ALERT` **Critical** (fail-closed nên không thể xảy ra bình thường ⇒ nghi dòng bị xoá).
   - `InProgress` quá `RequestStaleMinutes` và chưa có `END` → đặt `State = Error`, ghi `REQUEST.END` (Error, "gián đoạn") + `REQUEST.INTERRUPTED`: liệt kê **mọi bản ghi mang `RequestId` đó** (Get `LabLots`, `LabPreps`, `LabPrepItems`, `LabLedger`, `LabTestUsage`) và gửi Admin kiểm tra tay. Không tự chạy lại.
   - `InProgress` nhưng đã có `END` → đặt `State` theo `END`.
   - `Done/Rejected/Error` nhưng thiếu `END` → `INTEGRITY.ALERT` Important (C02 cuối đã thất bại).
2. **Dòng bị sửa.** Với `LabAudit`, `LabLedger`, `LabPrepItems`, `LabTestUsage`: Get items `Modified ge <lần chạy trước>` rồi *Filter array* chọn dòng có `Modified − Created > 60 giây` → mỗi dòng một `INTEGRITY.ALERT` **Critical** (list, `ID`, `Modified By`, giờ sửa). Tài khoản flow không có quyền Edit trên các list này nên mọi hit đều đáng điều tra.
3. **Dòng bị xoá.** *Send an HTTP request to SharePoint* `GET _api/web/lists/getbytitle('<list>')?$select=ItemCount,LastItemDeletedDate` cho `LabAudit`, `LabLedger`, `LabPrepItems`, `LabTestUsage`, `LabRequests`, `LabLots`, `LabPreps`. `LastItemDeletedDate` khác giá trị lưu ở `State_<list>_LastDeleted`, hoặc `ItemCount` nhỏ hơn lần trước → `INTEGRITY.ALERT` **Critical** (gợi ý kiểm thùng rác site và Purview). Lưu giá trị mới.
4. **Người có quyền cao thay đổi ngoài app.** `GET _api/web/AssociatedOwnerGroup/Users?$select=Email` so với `State_OwnersSnapshot` → khác thì Critical. Nhóm `LabChem Admins` so với `LabRoles` (`Role = Admin`, `IsActive`): lệch thì Important (R-04).
5. **Truy cập bị từ chối dồn dập.** Get `LabAudit` `Title eq 'ACCESS.DENIED' and Created ge now−24h`, nhóm theo `ActorEmail`; từ 5 lần trở lên → Important.
6. *(Tuỳ chọn, cần xác nhận quyền/độ trễ)* tài khoản trong `LabRoles` đã bị vô hiệu ở Entra (Office 365 Users — *Get user (V2)*, `accountEnabled = false`) → Important "thu hồi vai trò" (người nghỉ việc).
7. Có cảnh báo nào thì gửi email tổng hợp cho `AlertEmails`. Ghi `JOB.RUN` kết thúc (Success hoặc Warning kèm số liệu).

> **Giới hạn:** S03 chạy bằng cùng tài khoản dịch vụ; ai chiếm được tài khoản đó có thể tắt nó. Bù bằng email hằng ngày của S01 (mất email là tín hiệu) và Purview audit, vốn nằm ngoài tầm tay của tài khoản dịch vụ. Các lệnh `LastItemDeletedDate`, `AssociatedOwnerGroup` cần xác nhận trên tenant thật (mục 14).

## 14. Việc cần làm khi dựng flow

- Đặt tên action có nghĩa (`Create_Lot`, `Create_Ledger_Receive`...) vì biểu thức tham chiếu theo tên.
- Bật *Secure inputs/outputs* cho các action chứa email/Detail nếu tenant có yêu cầu bảo mật log (và luôn bật cho `LAB-C02`).
- Mỗi flow có action "Terminate" ở mọi nhánh từ chối để không chạy tiếp, và **mọi nhánh đều đi qua Khối kết thúc** (không có lối thoát nào bỏ qua nhật ký).
- Gắn flow vào app: *Power Apps → Power Automate → Add flow*; vì dùng một input `payload` nên đổi schema chỉ cần sửa JSON ở hai đầu.
- **Cần xác nhận trên tenant thật** (chưa chạy được ở đây):
  1. `Create item` vào cột `Title` đặt *duy nhất* thất bại với lỗi trùng và nhánh *run after: has failed* bắt được (cơ chế claim ở 0.6).
  2. Header `x-ms-user-email-encoded` có trong trigger PowerApps (V2) và là email trùng với khoá `LabRoles.Title` (chứ không phải UPN khác alias).
  3. Cột *Created*/*Modified* đánh index được qua `Set-PnPField`; lọc theo `Modified` không vướng ngưỡng 5.000.
  4. `LastItemDeletedDate` và `ItemCount` trả về đúng từ `_api/web/lists/getbytitle(...)`; `AssociatedOwnerGroup/Users` đọc được bằng tài khoản dịch vụ.
  5. Permission level tuỳ biến thật sự không còn `DeleteVersions` (`Get-PnPRoleDefinition`).
  6. Retry policy của action Create item trong C02 và thời gian chạy đo được của F01 với 20 chai khi đã thêm nhật ký.
