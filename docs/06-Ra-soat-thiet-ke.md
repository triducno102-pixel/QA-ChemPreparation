# 06 — Rà soát thiết kế (bảo mật · kiểm toán · nghiệp vụ · kiểm thử)

## 1. Kết luận

Khung thiết kế (sổ cái, mọi thao tác ghi qua flow, đối soát hằng đêm) là **đúng hướng**, nhưng khi rà soát với góc nhìn kiểm toán, **phần nhật ký chưa đủ**: có những thao tác để lại *không một dấu vết*, và cơ chế chống ghi trùng có khe hở. Em đã **sửa phần nhật ký ngay trong thiết kế** (schema, flow, màn hình, kiểm thử) theo yêu cầu "ghi log đầy đủ, không thể bỏ qua". Những điểm còn lại cần anh quyết về nghiệp vụ nên em để dạng đề xuất.

| | Số lượng |
|---|:-:|
| Phát hiện mức **Cao** | 6 |
| Mức Trung bình | 19 |
| Mức Thấp | 6 |
| Tính năng nên có thêm | 6 |
| **Đã sửa trong thiết kế** | 18 |
| Giảm nhẹ một phần (RS-19, RS-30) | 2 |
| Ghi nhận, không đổi (RS-27, RS-28) | 2 |
| **Chờ anh quyết / xác nhận** (RS-15…18, 21…25) | 9 |

**Sáu điểm nặng nhất** (chi tiết ở các bảng dưới):

1. **RS-01** — Admin sửa danh mục, cấu hình và *cả vai trò* bằng `Patch` trực tiếp: không qua flow nên **cấp quyền Admin cho ai đó không để lại nhật ký**, và quyền *Contribute* còn cho phép xoá.
2. **RS-02** — Nhật ký chỉ ghi ở *cuối* flow: flow chết giữa chừng thì dữ liệu đã đổi mà **không có dòng nhật ký nào**.
3. **RS-03** — Chống ghi trùng chỉ kiểm "đã có `Success` chưa": hai lần gọi song song đều lọt qua, và gửi lại sau khi flow chết giữa chừng sẽ **tạo trùng toàn bộ chai**.
4. **RS-04** — Danh tính chỉ là cột *Người*: có thể không ghi được cho tài khoản không phân giải được (đúng những người lạ cần ghi nhất), và hiển thị tên *hiện tại* thay vì danh tính lúc đó.
5. **RS-15** — Admin tự điều chỉnh/huỷ/vô hiệu tồn, kể cả chai chính mình dùng, **không ai duyệt**.
6. **RS-21** — Hạn dùng được kiểm theo *ngày người dùng nhập*: ghi lùi ngày là dùng được hoá chất đã hết hạn.

## 2. Phạm vi và giới hạn của đợt rà soát

- **Đã rà soát:** toàn bộ tài liệu 01–05, schema, script tạo list/phân quyền, công thức Power Fx mẫu, bộ ca kiểm thử — bằng cách đọc và suy luận từng luồng (bình thường, từ chối, lỗi giữa chừng, gọi song song, người không có quyền, người có quyền cao làm sai).
- **Chưa làm được:** chạy thử. Chưa có tenant/environment nên **không có gì trong đợt này được chạy thật** — kể cả phần nhật ký mới. Các điểm giả định về hành vi của SharePoint/Power Automate nằm ở [03 §14](03-Power-Automate.md); bản sửa chỉ đáng tin sau khi qua các ca T-AU trên tenant thật.
- Mức độ: **Cao** = có thể mất dấu vết, mất/sai dữ liệu hoặc qua mặt kiểm soát; **Trung bình** = sai lệch có điều kiện hoặc làm yếu kiểm soát; **Thấp** = nên biết/nên làm.

## 3. Đã đổi gì trong thiết kế để log đầy đủ

Yêu cầu của anh: ghi log trong ứng dụng **không thể bỏ qua, ghi đầy đủ**. Bảng này liệt kê từng thay đổi và nơi nó nằm, để anh kiểm tra.

| # | Thay đổi | Nằm ở |
|---|---|---|
| 1 | **Ghi trước, làm sau.** Flow ghi dòng `Started` trước khi đổi bất cứ thứ gì. Nếu không ghi được log thì thao tác bị dừng, không đổi dữ liệu nào (fail-closed). | [03 §2.2](03-Power-Automate.md) bước 0.7 |
| 2 | **Mọi yêu cầu có đủ dòng đầu và cuối**, kể cả bị từ chối, của người không có quyền, payload hỏng, gửi trùng hoặc gặp lỗi. | [03 §2.2, §2.4](03-Power-Automate.md) |
| 3 | **Mỗi chai hay dung dịch bị đổi có một dòng riêng**, kèm giá trị trước/sau và lý do. Danh tính là email do máy chủ xác định, kèm vai trò lúc đó (không dùng cột "Người"). | [03 §2.5–2.7](03-Power-Automate.md); [02](02-Mo-hinh-du-lieu.md) `LabAudit` (17 cột) |
| 4 | **Một mã yêu cầu (`RequestId`)** nối log, sổ cái và mọi bản ghi được tạo ra; sổ `LabRequests` chặn chạy trùng. | [02](02-Mo-hinh-du-lieu.md) `LabRequests`; [03 §2.2](03-Power-Automate.md) bước 0.6 |
| 5 | **Sửa danh mục, cấu hình, vai trò chỉ qua flow mới `LAB-F05`**, bắt buộc lý do. Admin chỉ còn quyền đọc. | [03 §11](03-Power-Automate.md); [05 §2.2](05-Bao-mat-va-Kiem-thu.md); script phân quyền |
| 6 | **`LAB-F06`** ghi các sự kiện do app báo: in nhãn (in lại được đánh dấu), mở màn Nhật ký, bị từ chối vào app. | [03 §12](03-Power-Automate.md); [04 §4.9, §4.11, §4.12](04-Power-Apps.md) |
| 7 | **`LAB-S03`** phát hiện log hoặc sổ cái bị sửa hay xoá ngoài app, đổi nhóm quản trị, yêu cầu thiếu đầu hoặc cuối. | [03 §13](03-Power-Automate.md) |
| 8 | **Báo cáo hằng ngày** và email ngay khi có sự kiện mức Critical. Không thấy email trong ngày là tín hiệu có vấn đề. | [03 §2.4, §8](03-Power-Automate.md) |
| 9 | **Màn Nhật ký** cho Admin và Reviewer, và tab Nhật ký ở màn chi tiết; đã có trong bản mockup (`mockup/index.html#audit`). | [04 §4.4, §4.12](04-Power-Apps.md) |
| 10 | **Sổ cái chỉ thêm** (không còn sửa `BalanceAfter`); bỏ quyền xoá phiên bản; đánh index `Created`/`Modified`. | [05 §2.2](05-Bao-mat-va-Kiem-thu.md); script |
| 11 | **Kiểm thử:** thêm 20 ca (T-IN-11, T-PF-04 và T-AU-01…18), tổng 85 ca (65 → 85; sau đó thêm 7 ca về nhiều người cùng thao tác ở RS-37 nên tổng là 92). Trong đó 18 ca về log, gồm ngắt flow giữa chừng, khoá quyền ghi log, Owner sửa hoặc xoá một dòng. | [05 §6.2](05-Bao-mat-va-Kiem-thu.md) |
| 12 | **Hai lỗi logic sửa kèm:** F02 (nếu bước tạo dung dịch lỗi sau khi đã trừ nguyên liệu thì nguyên liệu mất, dung dịch rỗng) và F01 (ghi mã vào biến mảng trong vòng lặp song song nên có thể mất mã). | [03 §5, §3](03-Power-Automate.md) (RS-14, RS-12) |

### Giới hạn thật của phần log

- Log ghi **thay đổi và quyết định**, **không ghi từng lượt xem** dữ liệu: người có quyền đọc có thể đọc thẳng trên SharePoint và app không chặn được. Nếu quy định bắt buộc ghi lượt xem thì cần giải pháp khác (câu hỏi 15 ở [05 §7](05-Bao-mat-va-Kiem-thu.md)).
- **Owner của site vẫn sửa được** log và sổ cái. Hệ thống chỉ **phát hiện** (`LAB-S03`, Purview, xuất lưu trữ kèm mã băm) chứ không ngăn tuyệt đối.
- Sự kiện do app báo (in nhãn, mở nhật ký) **có thể bị bỏ qua**, và `Print()` chỉ cho biết người dùng đã bấm in chứ không biết giấy có ra thật.
- Toàn bộ phần log mới **chưa chạy thử** trên tenant thật; các giả định cần xác nhận nằm ở [03 §14](03-Power-Automate.md).

## 4. A — Nhật ký và dấu vết (đã sửa trong thiết kế)

| ID | Mức | Phát hiện | Đã làm / đề xuất | Tình trạng |
|---|---|---|---|---|
| RS-01 | **Cao** | Màn Quản trị `Patch` thẳng vào danh mục/cấu hình/vai trò (Admin có *Contribute*). Không có `LabAudit`; đổi `RequireIncomingRelease`, `ReportUrlAllowedHosts`, cấp Admin cho người khác đều vô hình. Contribute gồm cả quyền xoá, mâu thuẫn "không ai xoá được". | Flow mới `LAB-F05 AdminData` là đường duy nhất; Admin chỉ còn quyền Read; có lý do, trước/sau, mức Critical + email ngay; chặn tự hạ quyền mình và bỏ Admin cuối ([03 §11](03-Power-Automate.md)) | Đã sửa |
| RS-02 | **Cao** | Nhật ký chỉ ghi ở cuối flow. Flow chết sau khi đã tạo chai/trừ tồn thì thay đổi tồn tại mà không có dấu vết. | `REQUEST.START` ghi **trước**, ghi không được thì không làm (fail-closed); mọi bản ghi mang `RequestId`; `LAB-S03` đối chiếu và liệt kê bản ghi tạo dở ([03 §2.2, §13](03-Power-Automate.md)) | Đã sửa |
| RS-03 | **Cao** | Chống ghi trùng bằng "đã có `Success` trong audit": hai lần gọi song song đều lọt; flow chết trước khi ghi `Success` thì lần gửi lại tạo trùng. | `LabRequests` duy nhất theo `RequestId`, nhận trước khi làm; trả `Done`/`Busy`/`Interrupted`; không tự chạy lại; app sinh `RequestId` mới sau `Rejected` ([03 §2.2](03-Power-Automate.md), [04 §4.4](04-Power-Apps.md)) | Đã sửa |
| RS-04 | **Cao** | `Actor` là cột Người: ghi có thể lỗi với tài khoản không phân giải được (khách, đã vô hiệu, người lạ gọi API); hiển thị tên hiện tại; không có vai trò lúc đó. | `ActorEmail` (văn bản bất biến, do server xác định) + `ActorName` + `ActorRole` lúc đó; luôn ghi được kể cả `None` | Đã sửa |
| RS-05 | Trung bình | `LabAudit` thiếu trước/sau, lý do riêng, mức, nguồn, ID đối tượng; `Title` hành động gõ tự do nên không lọc/đếm được. | Schema mới (17 cột) + danh mục sự kiện cố định ([03 §2.6](03-Power-Automate.md)); `LAB-C02` kiểm mã, mã lạ vẫn ghi thành `AUDIT.INVALID_ENTRY` | Đã sửa |
| RS-06 | Trung bình | Sổ cái nói là "chỉ thêm" nhưng `LAB-C01` sửa `BalanceAfter` sau khi ghi ⇒ phải cấp quyền Edit ⇒ dòng sổ cái sửa được. | Không sửa dòng đã ghi; `BalanceAfter` chỉ để tham khảo; `LabLedger` chuyển sang *Append Only* | Đã sửa |
| RS-07 | Trung bình | `LAB-S01` đánh dấu hết hạn hàng loạt nhưng chỉ ghi một dòng tổng kết: không biết chai nào đổi trạng thái lúc nào. | Mỗi đối tượng một dòng `LOT.EXPIRE`/`PREP.EXPIRE`; S02 tương tự (`STOCK.RECONCILE_FIX`, `RECORD.CODE_REPAIRED`) | Đã sửa |
| RS-08 | Trung bình | Không phát hiện được sửa/xoá ngoài app (Owner, quản trị SharePoint); R-09 chỉ ghi "Thấp". | `LAB-S03 IntegrityWatch`: dòng bị sửa, dòng bị xoá, đổi nhóm Owners, thiếu cặp Started–kết thúc; nâng R-09 lên Trung bình; Purview + xuất lưu trữ kèm mã băm | Đã sửa (cần xác nhận trên tenant) |
| RS-09 | Trung bình | Ma trận quyền cho Reviewer xem nhật ký nhưng chỉ Admin có màn; `scrDetail` không có nhật ký của đối tượng. | `scrAudit` (Admin, Reviewer) với bộ lọc, trước/sau, "Xem cả yêu cầu"; tab Nhật ký ở chi tiết ([04 §4.4, §4.12](04-Power-Apps.md)) | Đã sửa |
| RS-10 | Trung bình | Sự kiện phía app không được ghi: in/in lại nhãn (hai nhãn cùng mã dán lên hai chai), bị từ chối vào app, mở nhật ký. | `LAB-F06 LogEvent` (`Source = ClientReport`); in lại tự đánh dấu Important. Nói rõ giới hạn: `Print()` không chứng minh giấy đã in; lượt xem dữ liệu không ghi được | Đã sửa một phần (giới hạn: R-13) |
| RS-11 | Trung bình | Nhật ký không ai rà soát; không có báo cáo sự kiện Critical; cảnh báo ngừng gửi thì không ai biết. | Email Critical ngay; báo cáo hằng ngày trong S01 (luôn gửi — mất email là tín hiệu); rà soát hằng tháng có ký xác nhận trong runbook ([05 §4](05-Bao-mat-va-Kiem-thu.md)) | Đã sửa (cần quyết định câu 14) |
| RS-12 | Thấp | F01 *Append to array variable* `codes` trong vòng lặp Concurrency = 5: biến không an toàn khi song song, có thể mất mã. | Đọc lại theo `RequestId` rồi *Select* sau vòng lặp ([03 §3 bước 6b](03-Power-Automate.md)) | Đã sửa |
| RS-13 | Trung bình | `Sort(LabLedger, Created)` ở Trang chủ: cột `Created` không có index, sổ cái vượt 5.000 dòng thì truy vấn bị chặn. | Sắp theo `ID`; đánh index `Created`/`Modified` cho list append-only (script) | Đã sửa |
| RS-14 | Trung bình | F02 chỉ rollback khi lỗi ở vòng thành phần; nếu bước `PrepCreate` lỗi sau khi đã trừ hết thì **nguyên liệu mất, dung dịch rỗng**. | Bước 9 nằm trong rollback; S02 phát hiện dung dịch có `PrepUse` mà tổng sổ cái bằng 0 ([03 §5, §9](03-Power-Automate.md)) | Đã sửa |

## 5. B — Phân quyền và tách nhiệm

| ID | Mức | Phát hiện | Đề xuất | Tình trạng |
|---|---|---|---|---|
| RS-15 | **Cao** | Admin tự `Adjust`/`Dispose`/`Void` không ai duyệt, kể cả chai mình đã dùng — cách che hao hụt dễ nhất. | Đã giảm nhẹ: lý do + mã lý do bắt buộc, email Critical ngay, rà soát hằng tháng. **Chưa đủ:** nên cần người thứ hai (Reviewer) duyệt khi vượt ngưỡng (ví dụ > 10% lượng ban đầu, hoặc chai đã dùng trong pha). | **Chờ anh quyết** (câu 17) |
| RS-16 | Trung bình | `Release` hoá chất kiểm nhập: Admin vừa đăng ký vừa Release được. BR-08 (4 mắt) chỉ áp cho dung dịch. | Thêm quy tắc: người Release ≠ người đăng ký (`RegisteredBy`) | Đề xuất (nhỏ, đưa vào F04 nếu anh đồng ý) |
| RS-17 | Trung bình | Mỗi người một vai trò. Phòng nhỏ sẽ cho mọi người làm Admin để vừa pha vừa duyệt ⇒ phá tách nhiệm. | `LabRoles.Role` thành đa lựa chọn (Analyst + Reviewer); Admin thiên về quản trị; BR-08 vẫn bảo đảm duyệt ≠ pha | **Chờ anh quyết** |
| RS-18 | Trung bình | Khoá danh tính là email: nếu email khác UPN/alias thì từ chối nhầm; đổi tên/email thì mất vai trò. Header danh tính chưa kiểm chứng. | Nhật ký đã lưu nguyên giá trị lúc đó. Cần xác nhận T-SEC-01; cân nhắc khoá bằng định danh bất biến nếu header cung cấp | Cần xác nhận trên tenant |
| RS-19 | Trung bình | Thu hồi quyền khi nhân viên nghỉ: không có phát hiện tài khoản đã bị vô hiệu. | S03 bước tuỳ chọn so với Entra (`accountEnabled`) + runbook rà soát vai trò mỗi quý ([05 §4](05-Bao-mat-va-Kiem-thu.md)) | Giảm nhẹ một phần |
| RS-20 | Thấp | *Contribute* gồm `DeleteVersions`: người sửa được item còn xoá được lịch sử phiên bản. | Loại `DeleteVersions` khỏi hai permission level tuỳ biến | Đã sửa (xác nhận bằng `Get-PnPRoleDefinition`) |

## 6. C — Logic nghiệp vụ

| ID | Mức | Phát hiện | Đề xuất | Tình trạng |
|---|---|---|---|---|
| RS-21 | **Cao** | BR-03 kiểm `ExpiryDate ≥ ngày giao dịch`, mà `usedDate`/`prepDate` do người dùng nhập (F02 cho lùi 7 ngày, F03 không giới hạn dưới): ghi lùi ngày để dùng hoá chất đã hết hạn vẫn qua. | Đã làm: chênh lệch so với giờ máy chủ ghi vào nhật ký (`backdatedHours/Days`) để kiểm toán thấy. **Chưa đổi luật.** Đề xuất: kiểm hạn theo **ngày máy chủ**; ghi bù tối đa N ngày, bắt buộc lý do, quá N chỉ Admin | **Chờ anh quyết** (câu 16) |
| RS-22 | Trung bình | Hoá chất không có hạn dùng (hoặc chỉ "ngày kiểm tra lại") không đăng ký được: F01 và ô nhập bắt buộc `expiryDate > receivedDate`. | `ExpiryType` (Hạn dùng · Kiểm tra lại · Không có) và `DefaultShelfLifeDays` ở danh mục | Đề xuất — hỏi lab có loại này không |
| RS-23 | Trung bình | Thiết kế bắt phải có **số biên bản ngay lúc dùng**, nhưng biên bản thường chỉ có sau khi thử xong. Người dùng sẽ chọn "Không gắn biên bản" ⇒ mất truy xuất. | Ghi theo **mã mẫu / phiếu công việc** trước, **nối số biên bản sau** bằng dòng liên kết chỉ thêm; báo cáo "đã dùng nhưng chưa gắn biên bản quá N ngày" | **Chờ anh quyết** (câu hỏi 1) |
| RS-24 | Trung bình | Số biên bản nhập tự do (hoa/thường, khoảng trắng, gạch nối) ⇒ truy xuất theo số biên bản sót. | Chuẩn hoá `Upper(Trim(...))`; mẫu định dạng cấu hình `ReportNoPattern`; gợi ý từ lần nhập trước | Đề xuất (nhỏ) — cần biết mẫu số biên bản |
| RS-25 | Trung bình | Dung dịch `Pending` vẫn dùng được; khi bị `Rejected` sau đó không có danh sách biên bản bị ảnh hưởng. | Cấu hình `RequirePrepApproval` (chặn dùng khi chưa duyệt) và khi Reject tự liệt kê biên bản bị ảnh hưởng gửi Admin | **Chờ anh quyết** (câu 3) |
| RS-26 | Trung bình | Đổi `BaseUnit` của hoá chất khi đã có chai ⇒ tổng tồn cộng lẫn đơn vị, cảnh báo % sai. | `LAB-F05` chặn đổi `BaseUnit` khi đã có chai | Đã sửa |
| RS-27 | Thấp | Mã `IN-yy-nnnnn` dùng `ID` 5 chữ số; vượt 99.999 thì mã dài hơn và regex nhận diện không khớp. | Với vài nghìn chai/năm đủ ~20 năm; ghi nhận, sửa regex khi cần | Ghi nhận |
| RS-28 | Thấp | Số lượng 4 chữ số thập phân (0,1 mg / 0,1 µL). | Đủ cho phòng lab thông thường; kiểm với cân vi lượng/pipet nếu có | Ghi nhận |
| RS-29 | Thấp | Cột kiểu Date của SharePoint/Power Apps hay lệch 1 ngày do múi giờ — với hạn dùng là vấn đề an toàn. | Thêm T-IN-11 | Đã thêm ca kiểm thử |
| RS-30 | Thấp | Hoá chất hết hạn vẫn còn tồn cần quy trình huỷ có lý do và báo cáo hao hụt. | Đã thêm `ReasonCode` cho sổ cái; KPI "đã quá hạn còn tồn" đã có; nên thêm báo cáo hao hụt theo mã lý do | Một phần |
| RS-37 | Trung bình | Con số "còn lại" trên màn hình chỉ là ảnh chụp lúc tải: A và B cùng thấy 400 mL, A lưu trước thì B vẫn thấy số cũ. Flow vẫn chặn số âm nên **dữ liệu không sai**, nhưng thiết kế chưa nói app xử lý ra sao: app không làm mới, phản hồi từ chối không kèm số mới (người dùng phải tải lại, quét lại), và `Adjust` gửi con số tuyệt đối có thể đè lên số đã đổi. | Flow tính lại từ sổ cái khi lưu và trả `lines` (số mới từng dòng); app làm mới khi vào bước xác nhận và mỗi ~45 giây, báo "400 → 100 mL", gợi ý chai khác cùng hoá chất; tất cả-hoặc-không-gì; `Adjust` có `expectedQty`; **không cần quét lại** ([01 §5.5](01-Thiet-ke-tong-the.md)). Chưa làm: giữ chỗ (G11) | Đã sửa (giữ chỗ chờ quyết, câu 18) |

## 7. D — Tính năng nên có thêm (ngoài G1–G10)

| ID | Tính năng | Vì sao |
|---|---|---|
| RS-31 | **Kiểm tra khi nhận hàng**: số phiếu giao hàng/PO, tình trạng bao bì, nhiệt độ vận chuyển, người kiểm, kết quả (đạt/không đạt) | Hiện chỉ có cờ `Quarantine`; không ghi được *vì sao* cho phép dùng |
| RS-32 | **Danh mục nhà cung cấp / hãng** có trạng thái được duyệt | Hiện là văn bản tự do (gõ khác nhau); ISO/IEC 17025 §6.6 yêu cầu quản lý nhà cung cấp bên ngoài |
| RS-33 | **Chất chuẩn / CRM**: giá trị chứng nhận, độ không đảm bảo, ngày kiểm tra lại, quan hệ chuẩn gốc → chuẩn làm việc | Truy xuất chuẩn đo lường (17025 §6.5) cho phòng lab định lượng |
| RS-34 | **Chất đặc biệt / tiền chất**: sổ riêng, người chứng kiến, kiểm kê tăng cường | Nếu lab có (câu hỏi 9); luật hoá chất thường yêu cầu hồ sơ riêng |
| RS-35 | **Chuyển vị trí (G1) và kiểm kê (G6) nên coi là bắt buộc**, không phải gợi ý | Không có chúng, tồn kho phụ thuộc người dùng nhớ ghi — câu hỏi đầu tiên của kiểm toán viên |
| RS-36 | **Báo cáo cho đánh giá viên**: sổ cái/nhật ký theo kỳ, theo hoá chất; thống kê hao hụt theo mã lý do | Phục vụ đánh giá; hiện chỉ có xem trên màn hình |

## 8. Đối chiếu ALCOA+ (nguyên tắc toàn vẹn dữ liệu)

| Nguyên tắc | Thiết kế đáp ứng | Còn thiếu |
|---|---|---|
| **A**ttributable — truy được người làm | `ActorEmail`, `ActorName`, `ActorRole` do server xác định, ghi ở nhật ký và sổ cái | Khoá email (RS-18) |
| **L**egible — đọc được | Tiếng Việt, nhãn thân thiện, `scrAudit` | — |
| **C**ontemporaneous — ghi đúng lúc | Giờ máy chủ (`Created`); ghi bù được đánh dấu | Luật ghi bù (RS-21), biên bản nối sau (RS-23) |
| **O**riginal — bản gốc | Sổ cái, nhật ký chỉ thêm; version history | Owner vẫn sửa được ⇒ S03, Purview (R-09) |
| **A**ccurate — chính xác | BR-01…BR-17, đối soát S02 | Hạn dùng, ngày giờ do người dùng nhập |
| **C**omplete — đầy đủ | Mọi yêu cầu có Started + kết thúc, kể cả bị từ chối | Lượt xem không ghi được (R-13) |
| **C**onsistent — nhất quán | Danh mục sự kiện, mã lý do, `RequestId` xuyên suốt | — |
| **E**nduring — bền | Xuất lưu trữ hằng tháng kèm mã băm; retention | Thời gian lưu chưa chốt (câu 14) |
| **A**vailable — truy cập được | `scrAudit`, tab Nhật ký, bộ lọc theo mã/người/`RequestId` | — |

## 9. Cần anh quyết định

| # | Vấn đề | Khuyến nghị của em |
|---|---|---|
| 1 | **Ghi bù ngày** (RS-21): cho nhập thao tác đã xảy ra từ hôm qua? hạn dùng kiểm theo ngày nào? | Kiểm theo **ngày máy chủ**; cho ghi bù **tối đa 2 ngày**, bắt buộc lý do; quá đó chỉ Admin |
| 2 | **Điều chỉnh tồn của Admin** (RS-15) | Dưới 10% lượng ban đầu: Admin tự làm (có email). Trên ngưỡng, hoặc chai đã dùng trong pha: cần Reviewer duyệt |
| 3 | **Vai trò đa lựa chọn** (RS-17) | Có: Analyst + Reviewer cùng một người, BR-08 vẫn chặn tự duyệt việc của mình |
| 4 | **Dung dịch chưa duyệt có được dùng?** (RS-25, câu 3) | Chặn dùng khi `Pending` đối với phép thử có biên bản; cho cấu hình |
| 5 | **Biên bản có sau khi dùng?** (RS-23) | Cho ghi theo mã mẫu/phiếu công việc, nối biên bản sau, báo cáo tồn đọng |
| 6 | **Hoá chất không có hạn / chỉ kiểm tra lại** (RS-22) | Thêm `ExpiryType` nếu lab có loại này |
| 7 | **Thời gian lưu nhật ký, ai rà soát hằng tháng, có Purview không** (câu 14) | Lưu tối thiểu bằng thời gian lưu hồ sơ thử nghiệm; Reviewer luân phiên rà soát |
| 8 | **Có cần ghi lượt xem?** (câu 15) | Không, trừ chất đặc biệt; nếu có thì phải cân nhắc giải pháp khác SharePoint |
| 9 | **Ghi vào app trước hay sau khi rót?** (RS-37, câu 18) | Nếu ghi *sau* khi rót: không cần giữ chỗ; bị từ chối "không đủ" nghĩa là sổ sách đã lệch, báo Admin điều chỉnh tồn có lý do. Nếu ghi *trước*: cân nhắc G11 (giữ chỗ 10–15 phút) sau thí điểm |

## 10. Thứ tự xử lý đề xuất

1. Anh chốt các mục ở mục 9 và [05 §7](05-Bao-mat-va-Kiem-thu.md) (câu 14–17).
2. Dựng `LabRequests`, `LAB-C02`, `LAB-C01`, `LAB-F01` **trước tiên** và chạy T-AU-01…07 trên tenant để xác nhận các giả định ở [03 §14](03-Power-Automate.md) (cơ chế nhận yêu cầu duy nhất, header danh tính, tốc độ).
3. Dựng F02–F06 và S01–S03; chạy T-AU-08…18, đặc biệt T-AU-04/05 (ngắt giữa chừng, khoá nhật ký) và T-AU-11…13 (sửa/xoá/đổi nhóm).
4. Chạy một lượt **kiểm toán thử** (T-AU-17) trên dữ liệu thí điểm, rồi mới mở cho người dùng.
