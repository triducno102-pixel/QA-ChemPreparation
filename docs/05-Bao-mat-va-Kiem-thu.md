# 05 — Bảo mật, rủi ro và kế hoạch kiểm thử

## 1. Mô hình tin cậy

```
Người dùng ──(danh tính M365)──► Power Apps ──(đọc, quyền của chính họ)──► SharePoint Lists  (Read-only)
                                      │
                                      └─(payload JSON)─► Power Automate ──(tài khoản dịch vụ)──► SharePoint Lists (ghi)
                                                          ▲ kiểm tra: danh tính người gọi, vai trò, nghiệp vụ, RequestId
```

Bốn nguyên tắc:

1. **Không tin client.** App chỉ là giao diện; ẩn nút theo vai trò chỉ để dễ dùng. Mọi kiểm tra quyền và nghiệp vụ lặp lại ở flow.
2. **Người dùng không có quyền ghi trực tiếp** vào list nghiệp vụ; muốn thay đổi phải đi qua flow có kiểm tra và ghi nhật ký.
3. **Không xoá, chỉ thêm.** Sai thì đảo bút toán có lý do; sổ cái và nhật ký chỉ cho thêm.
4. **Không có nhật ký thì không có thao tác.** Mọi yêu cầu để lại dấu vết *trước khi* đổi dữ liệu, và mọi yêu cầu — kể cả bị từ chối, của người lạ, hoặc gặp lỗi — có đủ dòng bắt đầu và kết thúc ([03 §2.5](03-Power-Automate.md)).

## 2. Phân quyền

### 2.1 Vai trò nghiệp vụ (lưu ở `LabRoles`, flow kiểm tra phía server)

| Chức năng | Admin | Analyst | Reviewer | Viewer |
|---|:-:|:-:|:-:|:-:|
| Quét, tra cứu, xem tồn, truy xuất | ✔ | ✔ | ✔ | ✔ |
| Đăng ký hoá chất đầu vào (F01) | ✔ | ✔ | | |
| Đăng ký pha chế (F02) | ✔ | ✔ | | |
| Ghi nhận sử dụng / gắn biên bản (F03) | ✔ | ✔ | | |
| Duyệt dung dịch pha, Release hoá chất kiểm nhập (F04) | ✔ | | ✔ | |
| Điều chỉnh, Huỷ bỏ, Vô hiệu (F04) | ✔ | | | |
| Quản lý danh mục, vị trí, cấu hình, vai trò — **chỉ qua F05**, có lý do và giá trị trước/sau | ✔ | | | |
| Xem nhật ký kiểm toán (màn Nhật ký, tab Nhật ký ở chi tiết) | ✔ | | ✔ | |

Quy tắc tách nhiệm: người duyệt dung dịch ≠ người pha (BR-08). Nên có ít nhất hai Admin để Admin này duyệt việc của Admin kia. `F05` không cho Admin tự hạ quyền chính mình hay bỏ Admin cuối cùng; mọi hành động mức Critical (điều chỉnh/huỷ/vô hiệu tồn, đổi cấu hình, đổi vai trò) gửi email ngay tới `AlertEmails` — nên gồm ít nhất một người **không** phải người vừa thao tác.

### 2.2 Quyền SharePoint (áp bởi `New-LabChemLists.ps1 -ApplyPermissions`)

| List | Owner | Tài khoản dịch vụ | Admins | Analysts / Viewers | Reviewers |
|---|---|---|---|---|---|
| `LabCatalog`, `LabLocations`, `LabSettings`, `LabRoles` | Full | Ghi (không xoá) | **Read** | Read | Read |
| `LabLots`, `LabPreps` | Full | Ghi (không xoá) | Read | Read | Read |
| `LabLedger`, `LabPrepItems`, `LabTestUsage` | Full | **Chỉ thêm** | Read | Read | Read |
| `LabAudit` | Full | **Chỉ thêm** | Read | **Không** | Read |
| `LabRequests` | Full | Ghi (không xoá) | Read | **Không** | **Không** |

- Hai permission level tuỳ biến: *LabChem Writer (No Delete)* và *LabChem Append Only*; cả hai đều bỏ quyền **xoá item** và **xoá phiên bản** (`DeleteVersions` — nếu không, người sửa được item còn xoá được lịch sử phiên bản). Tên quyền cần kiểm lại bằng `Get-PnPRoleDefinition` trên tenant thật.
- **Không nhóm lab nào có quyền ghi trực tiếp, kể cả Admin.** Thiết kế trước cấp *Contribute* cho Admin trên danh mục/cấu hình/vai trò: *Contribute* gồm cả quyền xoá, nên mâu thuẫn với "không ai ngoài Owner xoá được", và mọi sửa đổi (kể cả cấp quyền Admin) không qua flow nên không có `LabAudit`. Nay Admin sửa qua `LAB-F05`.
- Ngoài nhóm Owner, **không ai có quyền xoá** item. Người dùng thường không thể sửa số lượng bằng giao diện SharePoint.
- Sổ cái (`LabLedger`) nay cũng **chỉ thêm**: `LAB-C01` không còn sửa `BalanceAfter` sau khi ghi.
- `LabRoles` (đọc được bởi mọi người dùng lab) cho biết ai giữ vai trò gì — chấp nhận ở quy mô lab; nếu không muốn, chuyển việc tra vai trò sang flow.

## 3. Kiểm soát theo mối đe doạ

| ID | Mối đe doạ | Kiểm soát | Kiểm thử |
|---|---|---|---|
| S-1 | Giả mạo danh tính người thao tác | Flow lấy người gọi từ header `x-ms-user-email-encoded` (hoặc `My profile` với connection của người chạy), **không** nhận email từ client; `ActorEmail` (văn bản bất biến), `RegisteredBy`, `PreparedBy` ghi từ danh tính này | T-SEC-01, T-AU-01 |
| S-2 | Người không có vai trò gọi thẳng flow qua API | Mỗi flow kiểm `LabRoles` ở bước 0.8 (sau khi đã ghi `REQUEST.START`); từ chối + ghi `ACCESS.DENIED` và dòng kết thúc | T-SEC-02, 06 |
| T-1 | Sửa tay `RemainingQty`, sổ cái, công thức pha | Quyền Read cho người dùng; versioning 500 phiên bản; `LAB-S02` đối soát hằng đêm và sửa theo sổ cái; ledger/prep-items/test-usage chỉ cho thêm | T-SEC-03, T-RM-03 |
| T-2 | Chèn dữ liệu độc hại qua payload (OData injection, công thức Excel, HTML) | Flow xác thực kiểu/độ dài mọi trường; chuỗi do người dùng **không bao giờ** nối vào `$filter` — lọc bằng `ID` số, `RequestId` phải đúng 36 ký tự GUID, mọi chuỗi còn lại phải escape `'` → `''`; dữ liệu hiển thị qua control Power Apps (không render HTML); nếu sau này xuất CSV/Excel thì thêm tiền tố `'` cho ô bắt đầu bằng `= + - @` | T-SEC-07 |
| R-1 | Chối bỏ thao tác | `LabAudit` (Started → từng đối tượng → kết thúc; thành công/từ chối/lỗi; `ActorEmail` do server xác định; trước/sau; lý do) + sổ cái mang `RequestId` + version history; không dựa vào run history của flow vì chỉ lưu ~28 ngày | T-AU-01…03, T-SEC-11 |
| R-2 | Thao tác không để lại dấu vết (flow chết giữa chừng, ghi nhật ký lỗi, đường ghi vòng qua flow) | Ghi `REQUEST.START` **trước** khi làm, ghi không được thì không làm (fail-closed); `RequestId` trên mọi bản ghi; không ai (kể cả Admin) ghi trực tiếp — mọi sửa đổi dữ liệu gốc qua F05; `LAB-S03` đối chiếu `LabRequests` ↔ `LabAudit` mỗi đêm | T-AU-04, 05, 10 |
| T-3 | Sửa/xoá nhật ký hoặc sổ cái để che dấu vết | Tài khoản flow chỉ có quyền Add và không có `DeleteVersions`; `LAB-S03` phát hiện dòng bị sửa (`Modified` ≠ `Created`), dòng bị xoá (`LastItemDeletedDate`, `ItemCount`) và thay đổi nhóm Owners; Purview audit + retention; xuất lưu trữ hằng tháng kèm mã băm | T-AU-11…13 |
| E-3 | Admin lạm quyền (tự điều chỉnh tồn, cấp quyền cho mình, nới kiểm soát) | Hành động Critical bắt buộc lý do + trước/sau + email ngay; F05 chặn tự đổi vai trò mình và bỏ Admin cuối; ≥ 2 Admin; Reviewer rà soát nhật ký hằng tháng | T-AU-08, 09 |
| D-2 | Làm ngập nhật ký / `LabRequests` bằng gọi liên tục | `ACCESS.DENIED` tối đa 1 dòng/giờ/người; `LAB-S03` báo ≥ 5 lần bị từ chối trong 24 giờ; mỗi payload bị giới hạn kích thước/số dòng | T-AU-15 |
| I-4 | Nhật ký lộ thông tin (payload có ghi chú, cách pha) | `LabAudit` chỉ Admin/Reviewer đọc; *Secure inputs/outputs* cho `LAB-C02` | T-SEC-04 |
| I-1 | Lộ dữ liệu cho người ngoài | Chia sẻ app cho **nhóm bảo mật** lab; tắt chia sẻ ngoài tổ chức và link "Anyone" trên site; không dùng nhóm "Everyone" | T-SEC-09 |
| I-2 | Lộ mã/URL qua dịch vụ tạo QR công cộng | Giai đoạn thử: chỉ gửi **mã nội bộ** (`IN-26-00042`) — không có tên hoá chất, tenant hay app ID; trước go-live thay bằng PCF tạo QR cục bộ hoặc dịch vụ nội bộ (rủi ro R-03) | T-SEC-12 |
| I-3 | Link biên bản/COA độc hại | Flow chỉ nhận `https://`, có thể giới hạn theo host (`ReportUrlAllowedHosts`); app kiểm tra lại trước `Launch()` | T-SEC-08 |
| D-1 | Quá tải: bấm liên tục, nhập hàng loạt | Khoá nút khi `varBusy`; `MaxBottlesPerReceipt`; idempotency theo `RequestId` | T-IN-07 |
| E-1 | Nâng quyền: Analyst tự điều chỉnh tồn | Điều chỉnh/huỷ chỉ Admin, kiểm ở flow; thao tác bắt buộc có lý do; lưu cả lúc bị từ chối | T-SEC-06 |
| E-2 | Chiếm tài khoản dịch vụ (ghi mọi thứ) | Không cấp giấy phép/hộp thư thừa, chặn đăng nhập tương tác, Conditional Access, giám sát sign-in; quyền tối thiểu (không xoá); 2 co-owner là Admin lab | Rà soát cấu hình |

## 4. Danh sách kiểm tra trước go-live

**Tenant / môi trường**
- [ ] Môi trường Dev → Test → Prod, đóng gói bằng Solution; flow và connection thuộc tài khoản dịch vụ, có 2 co-owner.
- [ ] Chính sách DLP: nhóm *Business* gồm SharePoint, Outlook, Approvals, Teams; không cho trộn với connector ngoài.
- [ ] Site SharePoint riêng cho LabChem; tắt chia sẻ ngoài; xoá "Everyone except external users"; chỉ nhóm `LabChem *` và Owner có quyền.
- [ ] Đã chạy script với `-ApplyPermissions` và kiểm tra lại bằng tài khoản Analyst/Viewer thật.
- [ ] Bật **Purview audit** và kiểm tra thấy được sự kiện sửa/xoá item, đổi quyền, đổi nhóm, đăng nhập của tài khoản dịch vụ; đặt thời gian lưu và retention (không cho xoá) cho các list nghiệp vụ, đặc biệt `LabAudit` và `LabLedger`, theo quy định hồ sơ của phòng lab. Đây là lớp bằng chứng nằm ngoài tầm tay của tài khoản dịch vụ.
- [ ] Cảnh báo lỗi flow gửi tới nhóm Admin (không chỉ người tạo).

**Ứng dụng**
- [ ] Thay `QRBaseUrl` bằng nguồn QR nội bộ/PCF; kiểm tra không còn lệnh gọi ra dịch vụ công cộng (Network trong Monitor).
- [ ] App checker: 0 cảnh báo delegation, 0 lỗi accessibility.
- [ ] Ít nhất 2 người có vai trò Admin; vai trò mặc định cho người lạ là `None`.
- [ ] Tìm trong app: **không còn** `Patch` / `Collect` / `SubmitForm` / `Remove` nào trỏ vào list `Lab*`; mọi nút ghi gọi flow.
- [ ] Mọi flow F01–F05 đi qua khối chuẩn ([03 §2.2](03-Power-Automate.md)); đã chạy T-AU-04 và T-AU-05 (ngắt giữa chừng; khoá quyền ghi nhật ký).

**Vận hành**
- [ ] Runbook: cấp/thu hồi vai trò (cập nhật cả `LabRoles` **và** nhóm SharePoint), xử lý cảnh báo đối soát, quy trình điều chỉnh tồn.
- [ ] **Lưu trữ nhật ký:** hằng tháng xuất `LabAudit` và `LabLedger` ra thư viện lưu trữ có retention; ghi lại số dòng và mã băm SHA-256 của tệp xuất ở một nơi khác (gửi cho Reviewer). Thử khôi phục từ thùng rác/versions.
- [ ] **Rà soát nhật ký hằng tháng:** Reviewer (không phải người thao tác) xem các sự kiện Critical, `ACCESS.DENIED`, `INTEGRITY.ALERT`, `REQUEST.INTERRUPTED`, đối chiếu với lý do ghi; ký xác nhận vào biên bản rà soát. Đây là kiểm soát làm cho nhật ký có giá trị.
- [ ] Theo dõi: email tổng hợp hằng ngày từ `LAB-S01` (gồm sự kiện Critical; luôn gửi, **không thấy email trong ngày = tín hiệu cần hỏi ngay**), cảnh báo lệch từ `LAB-S02`, cảnh báo toàn vẹn từ `LAB-S03`. Người nhận ≥ 2 người, trong đó có người không phải Admin vận hành.
- [ ] Quy trình thu hồi quyền khi nhân viên nghỉ/chuyển việc: vô hiệu `LabRoles` **và** gỡ khỏi nhóm SharePoint `LabChem *`; rà soát danh sách vai trò mỗi quý.

## 5. Rủi ro và hạn chế đã biết

| ID | Rủi ro / hạn chế | Mức | Cách xử lý hiện tại | Khi nào xử lý triệt để |
|---|---|---|---|---|
| R-01 | Instant flow không có concurrency control → hai người trừ cùng một chai trong vài giây có thể đua | Thấp | Kiểm tra lại sau khi ghi trong `LAB-C01`, bù `Reversal` nếu âm; `LAB-S02` đối soát | Nếu phòng lab đông người dùng đồng thời: chuyển sang Dataverse hoặc cơ chế khoá |
| R-02 | Nhập nhiều chai/nhiều thành phần gần ngưỡng chờ 2 phút của Power Apps | Thấp | Chạy song song 5 luồng, giới hạn 20 chai và 30 thành phần | Chuyển sang xử lý bất đồng bộ + thông báo khi xong |
| R-03 | QR sinh bởi dịch vụ công cộng (chỉ để thử) | **Trung bình** | Chỉ gửi mã nội bộ; cấu hình thay được | **Trước go-live** |
| R-04 | Vai trò duy trì ở hai nơi (`LabRoles` và nhóm SharePoint) dễ lệch | Trung bình | Runbook + kiểm tra định kỳ | Giai đoạn 2: flow đồng bộ |
| R-05 | Child flow/Solution cần environment có Dataverse và giấy phép phù hợp | Trung bình | Phương án thay: sao chép Scope vào từng flow | Xác nhận với IT trước khi bắt đầu |
| R-06 | Ngưỡng 5.000 item/delegation khi dữ liệu lớn (`LabAudit` lớn nhanh nhất: ~50.000–150.000 dòng/năm) | Thấp (hiện tại) | Index (kể cả `Created`, `Modified`), hàm delegable, sắp theo `ID`, KPI giới hạn 2.000 | Snapshot KPI bằng flow; lưu trữ ledger/nhật ký cũ theo năm |
| R-07 | Biên bản thử nghiệm nằm ngoài hệ thống: đổi tên/di chuyển file làm hỏng liên kết | Trung bình | Lưu `Số biên bản` làm khoá chính, link chỉ là tiện ích | Quy ước thư viện biên bản cố định; ID bền (nếu có) |
| R-08 | Header danh tính người gọi có thể không có ở mọi tenant | Trung bình | Phương án thay bằng `My profile (V2)` | Xác nhận ở T-SEC-01 |
| R-09 | Owner của site (và quản trị SharePoint) vẫn sửa/xoá được dữ liệu và nhật ký | **Trung bình** | Giới hạn số Owner; versioning; đối soát; `LAB-S03` phát hiện dòng bị sửa/xoá và đổi nhóm Owners; Purview audit; xuất lưu trữ hằng tháng kèm mã băm | Nếu quy định đòi bất biến thật sự: retention label dạng bản ghi hoặc lưu bản sao ở kho ngoài |
| R-10 | `Print()` hạn chế trên di động / chưa biết loại máy in nhãn | Thấp | In từ máy tính; chốt máy in và kích thước nhãn | Giai đoạn 2: flow sinh PDF nhãn |
| R-11 | Máy quét Zebra 1D (laser, ví dụ LS2208) không đọc được QR | Trung bình | Nhãn in thêm mã vạch Code 39 (tạo offline trong app, đã kiểm chứng thuật toán bằng bộ giải mã); cần thử bằng đúng máy | Chốt model máy quét ở giai đoạn 0 |
| R-12 | Control quét camera *Barcode reader* không chạy trong trình duyệt; ô nhập nhận dữ liệu từ máy quét phải giữ focus | Thấp | Máy cầm tay là cách chính (ô nhập + Timer); camera chỉ hiện trên điện thoại/tablet | Kiểm thử T-SC-02, T-SC-09 trên thiết bị thật |
| R-13 | Nhật ký **không ghi lượt xem** dữ liệu; sự kiện do app báo (in nhãn, mở nhật ký) có thể bị bỏ qua và `Print()` không chứng minh giấy đã in | Trung bình | Nói rõ phạm vi ([03 §2.5](03-Power-Automate.md) mục 13); `LAB-F06` đánh dấu `ClientReport`; Purview cho truy cập cấp site | Nếu quy định bắt buộc ghi lượt xem: cần giải pháp khác (Dataverse auditing) — câu hỏi 15 |
| R-14 | Các kiểm tra của `LAB-S03` dựa trên thuộc tính **chưa kiểm chứng trên tenant** (`LastItemDeletedDate`, index `Created`/`Modified`, `AssociatedOwnerGroup`, header danh tính) | Trung bình | Danh sách xác nhận ở [03 §14](03-Power-Automate.md) | Trước go-live: chạy T-AU-11…13 trên tenant thật |
| R-15 | Chiếm được tài khoản dịch vụ thì có thể tắt `LAB-S03` hoặc ghi nhật ký giả | Trung bình | Email `LAB-S01` hằng ngày (mất email là tín hiệu); Purview nằm ngoài tầm tài khoản dịch vụ; quyền tối thiểu; giám sát đăng nhập, Conditional Access | — |
| R-16 | Ghi nhật ký làm chậm thao tác (thêm vài lần gọi action mỗi yêu cầu) và phụ thuộc SharePoint: nhật ký lỗi thì thao tác dừng (cố ý) | Thấp | Gom entry một lần gọi C02; vòng song song 5 luồng; đo ở T-PF-02 | Xử lý bất đồng bộ nếu chậm; chấp nhận dừng thao tác khi không ghi được nhật ký |
| R-17 | Người lưu sau bị từ chối vì người khác vừa dùng (số trên màn hình đã cũ); nếu lab ghi vào app *sau* khi rót thì sổ sách lệch thực tế | Thấp–Trung bình | Flow tính lại từ sổ cái khi lưu; app làm mới trước khi lưu và mỗi ~45 giây; từ chối kèm số mới và gợi ý chai khác; không cho ghi vượt tồn (BR-02) | Giữ chỗ (G11) nếu lab ghi *trước* khi rót; quy trình báo Admin điều chỉnh khi sổ sách lệch |

## 6. Kế hoạch kiểm thử

### 6.1 Chiến lược
- **Môi trường:** Test riêng, sao từ Dev; dữ liệu giả có số lượng nhỏ cho chức năng và bộ dữ liệu lớn cho hiệu năng (5.000 chai, 40.000 dòng sổ cái).
- **Tài khoản thử:** 1 Admin, 2 Analyst, 1 Reviewer, 1 Viewer, 1 người không có vai trò, 1 người ngoài nhóm bảo mật.
- **Lớp kiểm:** (1) chức năng theo từng yêu cầu, (2) bất biến dữ liệu bằng truy vấn đối chiếu, (3) phân quyền/bảo mật, (4) đồng thời, (5) hiệu năng, (6) thiết bị thực (camera, súng quét, máy in), (7) UAT với người dùng thật.
- **Đối chiếu bất biến sau mỗi bài kiểm:** với mọi Lot/Prep, `RemainingQty` = Σ `QtyDelta` và ≥ 0.

### 6.2 Ca kiểm thử

**Đăng ký hoá chất đầu vào (yêu cầu 1)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-IN-01 | Nhập 1 chai hợp lệ | Mã `IN-yy-nnnnn`; `RemainingQty = InitialQty`; 1 dòng `Receive`; audit Success; chuyển sang màn in nhãn |
| T-IN-02 | Nhập 5 chai; hai người nhập đồng thời | 5 mã khác nhau mỗi người, không trùng, mỗi chai có dòng sổ cái |
| T-IN-03 | Hạn dùng ≤ ngày nhận | Từ chối, không tạo bản ghi nào |
| T-IN-04 | Nhập 500 mg cho chất có đơn vị gốc g | Lưu 0,5 g |
| T-IN-05 | Gọi flow trực tiếp với đơn vị khác nhóm (mL cho chất g) | Từ chối + audit; UI không cho chọn |
| T-IN-06 | `bottleCount` = 21 hoặc 0 | Từ chối |
| T-IN-07 | Bấm Lưu hai lần liên tiếp; ngắt mạng rồi thử lại | Chỉ một bộ bản ghi (cùng `RequestId`) |
| T-IN-08 | `coaLink` = `javascript:alert(1)` hoặc `http://` | Từ chối |
| T-IN-09 | `RequireIncomingRelease = true` | Trạng thái Quarantine, không pha/dùng được cho tới khi Release |
| T-IN-10 | Danh mục `IsActive = false` | Từ chối |
| T-IN-11 | Nhập hạn dùng 01/03/2028 và 29/02/2028 (và các ngày cuối tháng), mở lại ở app, danh sách SharePoint và email cảnh báo | Mọi nơi hiển thị đúng ngày, **không lệch 1 ngày** do múi giờ (lỗi quen thuộc của cột Date trong SharePoint/Power Apps) |

**Đăng ký pha chế (yêu cầu 2)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-PR-01 | Pha từ 2 chai hợp lệ | Mã `PC-…`; 2 dòng `LabPrepItems` có snapshot số lô; nguồn bị trừ đúng; `PrepUse` âm + `PrepCreate` dương; `RemainingQty = FinalQty` |
| T-PR-02 | Lượng dùng > còn lại | UI báo tại dòng; gọi flow trực tiếp vẫn bị từ chối; tồn nguồn không đổi |
| T-PR-03 | Thành phần Quarantine / Expired / Empty / Disposed / hết hạn | Chặn ở UI và flow |
| T-PR-04 | Hạn dùng pha > hạn sớm nhất của thành phần (bật `EnforcePrepExpiryLimit`) | Từ chối, nêu rõ thành phần giới hạn |
| T-PR-05 | Pha dung dịch làm việc từ dung dịch gốc (2 cấp) | Thành công; truy xuất thấy đủ 2 cấp |
| T-PR-06 | Thêm cùng một thành phần hai lần | Chặn |
| T-PR-07 | Gây lỗi giữa chừng (một chai bị người khác trừ cạn khi đang lưu) | Rollback: tồn nguồn về đúng, dung dịch bị Void, sổ cái có `Reversal` |
| T-PR-08 | Dung dịch `ReviewStatus = Rejected` dùng làm nguyên liệu/dùng thử nghiệm | Chặn |
| T-PR-09 | Reviewer trùng người pha duyệt | Từ chối (BR-08) |

**Theo dõi lượng còn lại (yêu cầu 3)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-RM-01 | Sau chuỗi nhập/pha/dùng/điều chỉnh | Bất biến `Remaining = Σ ledger` đúng; thanh còn lại và trạng thái hiển thị đúng |
| T-RM-02 | Hai Analyst cùng trừ một chai song song (script gọi đồng thời) | Không bao giờ âm; sau `LAB-S02` số liệu khớp sổ cái |
| T-RM-03 | Owner sửa tay `RemainingQty` trên SharePoint | `LAB-S02` khôi phục theo sổ cái, ghi audit, gửi cảnh báo |
| T-RM-04 | Nhiều giao dịch số lẻ (0,1 + 0,2 g …) | Không lệch số thực (làm tròn 4 số lẻ) |
| T-RM-05 | Qua ngày hết hạn | `LAB-S01` đánh dấu Expired; không dùng được; vẫn truy xuất được |
| T-RM-06 | Hoá chất có tồn chuẩn 1.000 mL, ngưỡng mặc định 20%; còn 190 mL rồi 210 mL | 190 mL: hiện "Cần mua thêm" ở KPI, tab gộp và email; 210 mL: không cảnh báo |
| T-RM-08 | Đặt `LowStockPct = 50` riêng cho một hoá chất, giữ mặc định ở hoá chất khác | Hoá chất riêng cảnh báo ở 50%, các hoá chất khác ở 20%; đổi `DefaultLowStockPct` chỉ ảnh hưởng nhóm dùng mặc định |
| T-RM-09 | Dùng hết sạch mọi chai của một hoá chất (còn 0) | Vẫn xuất hiện ở "Cần mua thêm" với 0% (không biến mất khỏi danh sách) |
| T-RM-10 | Chưa đặt `ParLevelQty`: nhập thêm chai làm tồn tổng vượt `PeakQty`; sau đó đặt `ParLevelQty` | `PeakQty` tăng theo lần nhập; khi có `ParLevelQty` thì mốc 100% dùng giá trị này |
| T-RM-07 | Dùng hết đúng bằng tồn | `Status = Empty`, ẩn khỏi danh sách "đang dùng", vẫn tra cứu |

**Ghi nhận sử dụng và truy xuất (yêu cầu 4)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-US-01 | Gắn 2 dung dịch vào 1 biên bản | 2 dòng `LabTestUsage`, trừ đúng, sổ cái `TestUse` có `RefCode = số biên bản` |
| T-US-02 | `purpose = Test` không có số biên bản | Từ chối |
| T-US-03 | Dùng vượt tồn | Từ chối, tồn không đổi |
| T-TR-01 | Truy xuất bằng mã `PC-…` | Đủ: thông tin, công thức, số lô NSX, link COA, danh sách biên bản (mở được link) |
| T-TR-02 | Truy xuất bằng mã `IN-…` qua 3 cấp pha | Thấy mọi dung dịch hậu duệ và mọi biên bản |
| T-TR-03 | Biên bản qua dung dịch hậu duệ | Hiện cột "qua dung dịch" |
| T-TR-04 | Mã không tồn tại / sai định dạng / chuỗi rất dài | Thông báo thân thiện, không lỗi, không điều hướng |
| T-TR-05 | Truy xuất đối tượng đã Empty/Expired/Disposed | Vẫn đầy đủ |

**QR và mã vạch (yêu cầu 5)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-SC-01 | Quét nhãn bằng camera trong app (iOS, Android) | Mở đúng chi tiết trong ≤ 3 giây |
| T-SC-02 | Máy Zebra cầm tay (USB, chế độ HID bàn phím) ở màn Quét — thử cả khi bật và khi tắt hậu tố Enter | Mở đúng chi tiết trong ≤ 1 giây, không cần bấm thêm; không cần quyền camera |
| T-SC-07 | Máy Zebra **1D (laser)** quét mã vạch Code 39 trên nhãn in thật | Đọc đúng mã; mở đúng chi tiết |
| T-SC-08 | Máy 2D hoặc điện thoại quét QR trên cùng nhãn | Đọc đúng mã |
| T-SC-09 | Bộ gõ tiếng Việt (Unikey/Telex) đang bật khi quét; Caps Lock bật | Mã vẫn nhận đúng, hoặc app báo "Không nhận ra mã" rõ ràng (không mở sai đối tượng) |
| T-SC-03 | QR `DeepLink` quét bằng camera điện thoại | Mở app đúng mã (cả trường hợp chưa đăng nhập) |
| T-SC-04 | Nhãn in 50 × 30 mm | Quét được ở 20–30 cm; thử dán lên chai cong, nhãn ướt, ánh sáng yếu |
| T-SC-05 | Quét mã lạ, URL ngoài, chuỗi 10.000 ký tự | App không treo, không mở trang ngoài |
| T-SC-06 | Quét ngay sau khi tạo (chưa nhận dữ liệu) | Tìm thấy hoặc báo rõ ràng, không lỗi |

**Bảo mật**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-SEC-01 | Gửi payload có trường giả `actor`/email người khác | Bản ghi mang danh tính thật của người gọi |
| T-SEC-02 | Viewer gọi thẳng flow F01–F05 bằng API | Từ chối + `LabAudit` (`ACCESS.DENIED`, Rejected) |
| T-SEC-03 | Analyst sửa/xoá item `LabLots`, `LabLedger` trên giao diện SharePoint | Không được |
| T-SEC-04 | Analyst/Viewer mở `LabAudit` | Không truy cập được |
| T-SEC-05 | Người không có trong `LabRoles` mở app | Màn `scrNoAccess`, không dữ liệu |
| T-SEC-06 | Analyst gọi `Adjust`/`Dispose`/`Void` | Từ chối |
| T-SEC-07 | `RequestId` = `' or 1 eq 1 or '`; tên chứa `'`, `=cmd\|'/c calc'!A1`, `<script>` | Từ chối `RequestId`; chuỗi khác lưu nguyên văn, không làm hỏng truy vấn, không thực thi |
| T-SEC-08 | `reportUrl` ngoài danh sách host cho phép (khi đã cấu hình) | Từ chối |
| T-SEC-09 | Người ngoài nhóm bảo mật mở link app | Không mở được |
| T-SEC-10 | Đổi chủ flow / đổi mật khẩu tài khoản dịch vụ | Flow không hỏng ngoài dự kiến; có cảnh báo khi connection lỗi |
| T-SEC-11 | Tìm trong run history/ audit có dữ liệu không cần thiết | Không có bí mật/token |
| T-SEC-12 | Theo dõi mạng khi sinh QR | Chỉ gọi tới nguồn đã duyệt; payload chỉ là mã nội bộ |

**Nhiều người cùng thao tác (T-CC)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-CC-01 | A và B cùng mở form pha với chai còn 400 mL; A lưu, dùng 300 mL; B (mở từ trước, vẫn thấy 400) nhập 200 mL rồi bấm Lưu | B bị từ chối "còn 100 mL"; **không có dòng sổ cái nào của B**; app cập nhật dòng đó thành 100 và gợi ý chai khác cùng hoá chất còn đủ; B sửa lượng hoặc chọn chai khác rồi lưu thành công (`RequestId` mới) mà **không phải quét lại** |
| T-CC-02 | Như trên, nhưng B sang bước Xác nhận sau khi A lưu | App tự đối chiếu và hiện "IN-…: 400 → 100 mL", khoá nút Lưu đến khi B bấm "Tôi đã xem" |
| T-CC-03 | Để form mở hơn một phút trong lúc người khác dùng chai | Sau tối đa ~45 giây số "còn lại" tự đổi, dòng đổi được tô nổi bật kèm giờ xem mới |
| T-CC-04 | Pha 3 thành phần; thành phần thứ 3 bị người khác dùng cạn trước khi B lưu | Cả yêu cầu bị từ chối, **không thành phần nào bị trừ**, dung dịch không được tạo; `lines` chỉ đúng dòng thứ 3 |
| T-CC-05 | A và B bấm Lưu cùng lúc (cách nhau dưới 2 giây, script gọi đồng thời) cho một chai chỉ đủ một người | Đúng một người thành công; người kia bị từ chối rõ ràng (hoặc yêu cầu được hoàn lại bằng `Reversal`); số dư **không bao giờ âm**; sau `LAB-S02` khớp sổ cái |
| T-CC-06 | `Adjust`: Admin mở hộp thoại thấy 200 mL, đếm được 180; trong lúc đó Analyst dùng 30 (còn 170); Admin bấm Lưu `newQty = 180` | Bị từ chối "Số dư vừa đổi (200 → 170)", không đổi gì; hộp thoại hiện 170 và yêu cầu đếm lại |
| T-CC-07 | Sau T-CC-01, B bấm Lưu lại bằng **cùng** `RequestId` (giả lập lỗi app) | Nhận lại đúng lời từ chối cũ, không ghi gì; app thật luôn dùng `RequestId` mới sau `Rejected` |

**Nhật ký kiểm toán (yêu cầu bắt buộc)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-AU-01 | Mỗi thao tác **thành công** của F01–F05 | Có `REQUEST.START`, các dòng đối tượng, `REQUEST.END` cùng `RequestId`; `ActorEmail`/`ActorRole` đúng người gọi; thời gian là giờ máy chủ (đổi giờ máy khách không ảnh hưởng) |
| T-AU-02 | Thao tác bị từ chối vì nghiệp vụ (hết hạn, vượt tồn, thiếu lý do…) | Có `START` + `END` Rejected kèm lý do; không có dòng đối tượng; dữ liệu không đổi |
| T-AU-03 | Người **không có trong `LabRoles`** (và Viewer) gọi thẳng F01/F04/F05 bằng API | `ACCESS.DENIED` + `END` Rejected với `ActorEmail` đúng, `ActorRole = None`; không dữ liệu nào đổi; vẫn ghi được dù tài khoản chưa từng vào site |
| T-AU-04 | Dừng F01 giữa chừng (huỷ run sau khi đã tạo 2/5 chai) | Có `START`; mọi bản ghi tạo ra mang `RequestId`; sau `RequestStaleMinutes`, S03 đặt `Error`, ghi `REQUEST.INTERRUPTED` liệt kê 2 chai và email Admin; gửi lại cùng `RequestId` nhận `Interrupted`, **không tạo thêm chai** |
| T-AU-05 | Tạm thu quyền Add của tài khoản flow trên `LabAudit`, rồi chạy F01/F04 | Flow từ chối ("không ghi được nhật ký"); **không** bản ghi hay dòng sổ cái nào bị đổi (fail-closed) |
| T-AU-06 | Gọi F01 hai lần **song song** với cùng `RequestId` | Chỉ một lần thực hiện; lần kia nhận `Busy` hoặc kết quả đã lưu; không trùng chai |
| T-AU-07 | Sau `Rejected`: gửi lại bằng API cùng `RequestId`; và dùng app | API nhận lại đúng lời từ chối cũ; app đã sinh `RequestId` mới nên lần sửa-rồi-gửi thành công |
| T-AU-08 | `Adjust`, `Dispose`, `Void`, `Release`, `Review` | Mỗi hành động một dòng riêng có `Reason`, `BeforeValue`/`AfterValue` đúng; mức Critical gửi email ngay tới `AlertEmails`; thiếu lý do/mã lý do thì bị từ chối (và vẫn có nhật ký) |
| T-AU-09 | F05: tạo/sửa/ngừng danh mục và vị trí; đổi cấu hình; cấp/đổi/ngừng vai trò | Mỗi lần có dòng trước/sau + lý do; đổi `BaseUnit` khi đã có chai bị chặn; tự hạ quyền mình và bỏ Admin cuối bị chặn; `SETTING.SET`, `ROLE.SET` là Critical + email |
| T-AU-10 | Admin sửa `LabCatalog`/`LabSettings`/`LabRoles` trực tiếp bằng giao diện SharePoint hoặc API | Không được (chỉ Read); chỉ sửa được qua F05 |
| T-AU-11 | Owner sửa tay một dòng `LabAudit`/`LabLedger`/`LabTestUsage` | S03 báo "dòng bị sửa" (Critical) kèm `ID` và `Modified By`; bản cũ còn trong version history |
| T-AU-12 | Owner xoá một dòng `LabLedger` (rồi dọn thùng rác) | S03 báo xoá (Critical) nhờ `LastItemDeletedDate`/`ItemCount` |
| T-AU-13 | Thêm người vào nhóm Owners hoặc `LabChem Admins` ngoài app | S03 báo (Critical với Owners; Important với lệch `LabRoles`) |
| T-AU-14 | S01 đánh dấu 3 chai hết hạn; S02 sửa 1 cache bị lệch | 3 dòng `LOT.EXPIRE` có mã; 1 dòng `STOCK.RECONCILE_FIX` có trước/sau; `JOB.RUN` đủ cặp |
| T-AU-15 | In nhãn lần 1 rồi in lại lần 2 cùng mã; mở màn Nhật ký; người không có vai trò mở app nhiều lần | `LABEL.PRINT` (lần 2 `reprint=true`, Important); `AUDIT.VIEW`; `ACCESS.DENIED` (≤ 1 dòng/giờ); đều `Source = ClientReport` |
| T-AU-16 | Reviewer dùng `scrAudit`: lọc theo mã/người/mức/`RequestId`, "Xem cả yêu cầu"; Analyst mở app | Kết quả đúng, trước/sau hiển thị; Analyst không thấy mục Nhật ký và không đọc được `LabAudit` |
| T-AU-17 | **Kiểm toán thử** trên một chai đã qua đủ vòng đời (nhập → release → pha → dùng → điều chỉnh → huỷ) | Dựng lại được toàn bộ (ai, khi nào, vì sao, bao nhiêu) chỉ từ `LabAudit` + `LabLedger` trong ≤ 10 phút, không cần hỏi ai, không có khoảng trống |
| T-AU-18 | Ghi chú/tên chứa `'`, `<script>`, `=cmd\|…` và ký tự tiếng Việt | Nhật ký lưu nguyên văn; không lỗi; không thực thi |

**Hiệu năng và dùng được**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-PF-01 | 5.000 chai, 40.000 dòng sổ cái: mở Tồn kho, tìm theo mã/tên/số lô | < 3 giây; không cảnh báo delegation |
| T-PF-02 | F01 với 20 chai; F02 với 30 thành phần (đã tính cả việc ghi nhật ký) | Mỗi flow < 60 giây |
| T-PF-04 | `LabAudit` 100.000 dòng: mở `scrAudit` lọc theo 7 ngày, theo mã, theo `RequestId` | < 3 giây; không cảnh báo delegation; không vướng ngưỡng 5.000 |
| T-PF-03 | Mở Trang chủ | < 4 giây |
| T-UX-01 | Analyst mới, không hướng dẫn: nhập 1 lô và pha 1 dung dịch | ≤ 5 phút, không cần hỏi |
| T-UX-02 | Điện thoại: quét → xem tồn → ghi dùng | ≤ 3 thao tác |
| T-UX-03 | Accessibility checker, tương phản, màn hình điện thoại/máy tính bảng | 0 lỗi nghiêm trọng; không cuộn ngang |
| T-UX-04 | Tiếng Việt có dấu trong app, email, nhãn | Hiển thị đúng |

### 6.3 Tiêu chí nghiệm thu theo yêu cầu

| Yêu cầu | Đạt khi |
|---|---|
| 1. Đăng ký hoá chất đầu vào | T-IN-01…11 đạt |
| 2. Đăng ký pha chế | T-PR-01…09 đạt |
| 3. Theo dõi lượng còn lại | T-RM-01…10 đạt; bất biến không vi phạm trong 2 tuần chạy thử |
| Nhiều người cùng thao tác | T-CC-01…07 đạt; người lưu sau luôn nhận số mới, không bao giờ có số âm, không bị bắt quét lại |
| 4. Truy xuất biên bản qua mã hoá chất pha | T-US-01…03, T-TR-01…05 đạt |
| 5. QR / mã vạch | T-SC-01…09 đạt trên thiết bị thật của phòng lab (đúng máy Zebra và máy in nhãn đang dùng) |
| Bảo mật | T-SEC-01…12 đạt, không còn rủi ro mức Cao |
| **Nhật ký kiểm toán** | T-AU-01…18 đạt, kể cả T-AU-04/05 (ngắt giữa chừng, khoá nhật ký) và T-AU-11…13 trên tenant thật; **không còn thao tác nào đổi dữ liệu mà không có nhật ký** |

## 7. Câu hỏi mở (cần anh/đơn vị xác nhận)

1. **Biên bản thử nghiệm** (xem định nghĩa ở [01 mục 3a](01-Thiet-ke-tong-the.md)) trong phòng lab anh gọi là gì (biên bản, báo cáo, phiếu kết quả…) và **hiện lưu ở đâu** (thư viện SharePoint, hệ thống khác, bản giấy)? Quyết định cách gắn liên kết và có cần tích hợp không.
2. **Một chai một mã QR** có đúng với cách làm việc không, hay theo lô?
3. **Có cần duyệt**: kiểm nhập (Quarantine → Release) và duyệt dung dịch pha (4 mắt)? Hiện thiết kế sẵn, mặc định tắt kiểm nhập, bật duyệt dung dịch ở mức ghi nhận.
4. **Máy quét Zebra** đang dùng là model nào (ví dụ LS2208, DS2208, DS2278…) — loại **1D (laser) hay 2D (imager)**, nối USB hay Bluetooth, nối với PC chạy trình duyệt hay Power Apps for Windows? **Máy in nhãn** nào và **kích thước nhãn**?
5. **Quy mô**: bao nhiêu chai/dung dịch mỗi năm, bao nhiêu người dùng đồng thời?
6. **Tiêu chuẩn áp dụng** (ISO/IEC 17025, GLP…) và **thời gian lưu hồ sơ**?
7. **Môi trường Power Platform**: có Dataverse/Solution không, loại giấy phép, có tài khoản dịch vụ và hộp thư gửi cảnh báo không?
8. **Đơn vị**: có cần các đơn vị khác (mol, %, đương lượng) hoặc chất tồn kho đếm theo cái (pcs) không?
9. Có cần **ảnh GHS/cảnh báo nguy hiểm** trên nhãn, và **kiểm soát chất thuộc diện đặc biệt** (tiền chất, chất độc) không?
10. **Ngôn ngữ**: chỉ tiếng Việt hay song ngữ?
11. **Cảnh báo sắp hết:** mốc 100% lấy từ *lượng tồn chuẩn* của từng hoá chất (hoặc tồn cao nhất đã đạt) và ngưỡng mặc định 20% có hợp lý không? Hay anh muốn so với từng chai, hoặc dùng số lượng tuyệt đối?
12. **Hạn dùng sau khi mở nắp** ([01 mục 8, G2](01-Thiet-ke-tong-the.md)): hoá chất/dung môi nào có hạn ngắn hơn sau khi mở, và có cần quản lý riêng không?
13. **Quy mô kho hiện tại:** khoảng bao nhiêu chai đang có? (quyết định công sức nạp tồn đầu kỳ và dán nhãn — G3)
14. **Nhật ký — thời gian lưu và người rà soát:** quy định của phòng lab yêu cầu giữ nhật ký bao lâu? Ai (Reviewer nào, không phải người thao tác) rà soát hằng tháng? Giấy phép có Purview Audit và retention label không?
15. **Có cần ghi cả lượt *xem* hồ sơ** (ví dụ với chất đặc biệt, hay ai đã tra cứu hồ sơ truy xuất)? Với SharePoint + Power Apps, việc này không đảm bảo được ở cấp dữ liệu (người có quyền đọc có thể đọc trực tiếp); nếu bắt buộc cần giải pháp khác.
16. **Ghi bù ngày:** cho nhập thao tác đã xảy ra từ hôm qua đến mấy ngày; có bắt buộc lý do không; hạn dùng kiểm theo *ngày thực xảy ra* hay *ngày nhập*? ([06 RS-19](06-Ra-soat-thiet-ke.md))
17. **Điều chỉnh tồn của Admin:** tự điều chỉnh được, hay cần người thứ hai duyệt khi vượt ngưỡng (ví dụ > 10% hoặc > X mL)? ([06 RS-13](06-Ra-soat-thiet-ke.md))
18. **Thứ tự làm việc:** người dùng ghi vào app **trước** khi rót/pha hay **sau** khi đã rót xong? Câu trả lời quyết định có cần giữ chỗ (G11) hay không, và việc bị từ chối "không đủ" nghĩa là gì ([01 mục 5.5](01-Thiet-ke-tong-the.md)).
