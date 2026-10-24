# LabChem.Schema.ps1
# Nguồn sự thật duy nhất (single source of truth) cho mô hình dữ liệu SharePoint.
#  - New-LabChemLists.ps1 đọc file này để tạo list/cột.
#  - docs/02-Mo-hinh-du-lieu.md được sinh ra từ file này (tránh lệch giữa tài liệu và thực tế).
# Quy ước:
#  - InternalName chỉ dùng ASCII, không dấu cách (Power Fx / OData an toàn).
#  - "Enum máy" (Status, TxnType, ItemType, SourceType, Role...) dùng khoá tiếng Anh; app ánh xạ sang nhãn tiếng Việt.
#  - "Nhãn nghiệp vụ" (ChemType, PrepType, HazardClass, StorageCondition...) dùng tiếng Việt trực tiếp.
#  - Quan hệ giữa list dùng cột Number (ID) + Text (mã snapshot), KHÔNG dùng Lookup column:
#    tránh giới hạn 12 lookup/view và lỗi delegation khi lọc theo lookup trong Power Apps.

function Fld {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, Position = 1)][string]$Display,
        [Parameter(Mandatory, Position = 2)]
        [ValidateSet('Text', 'Note', 'Number', 'Boolean', 'Choice', 'MultiChoice', 'Date', 'DateTime', 'Url', 'User')]
        [string]$Type,
        [string[]]$Choices = @(),
        [string]$Default = '',
        [switch]$Required,
        [switch]$Indexed,
        [int]$Decimals = -1,
        [double]$Min = [double]::NaN,
        [double]$Max = [double]::NaN,
        [string]$Note = ''
    )
    [pscustomobject]@{
        Name = $Name; Display = $Display; Type = $Type; Choices = $Choices; Default = $Default
        Required = [bool]$Required; Indexed = [bool]$Indexed; Decimals = $Decimals; Min = $Min; Max = $Max; Note = $Note
    }
}

$UnitChoices   = @('g', 'mL', 'pcs')
$StatusLot     = @('Quarantine', 'Available', 'InUse', 'Empty', 'Expired', 'Disposed')
$StatusPrep    = @('Available', 'InUse', 'Empty', 'Expired', 'Disposed')
$StorageChoice = @('15-25 °C (phòng)', '2-8 °C', '-20 °C', '-80 °C', 'Tủ chống cháy', 'Tủ hút', 'Tránh ánh sáng')

$LabSchema = [ordered]@{

    LabCatalog = @{
        Description  = 'Danh mục hoá chất (master data). Chỉ Admin chỉnh sửa.'
        TitleDisplay = 'Tên hoá chất'
        TitleIndexed = $true
        TitleUnique  = $false
        ViewFields   = @('LinkTitle', 'CasNumber', 'ChemType', 'Grade', 'BaseUnit', 'ParLevelQty', 'LowStockPct', 'IsActive')
        Fields       = @(
            Fld CasNumber       'Số CAS'                    Text    -Indexed
            Fld ChemType        'Loại'                      Choice  -Choices 'Chất gốc', 'Dung môi', 'Chất chuẩn', 'Dung dịch đệm', 'Môi trường', 'Khác' -Default 'Chất gốc'
            Fld Grade           'Cấp độ tinh khiết'         Choice  -Choices 'AR', 'GR', 'ACS', 'HPLC', 'LC-MS', 'Technical', 'CRM', 'Khác'
            Fld BaseUnit        'Đơn vị gốc'                Choice  -Choices $UnitChoices -Default 'g' -Required -Note 'Mọi số lượng của hoá chất này đều lưu theo đơn vị gốc (g, mL hoặc pcs).'
            Fld HazardClass     'Phân loại nguy hiểm (GHS)' MultiChoice -Choices 'Dễ cháy', 'Ăn mòn', 'Độc cấp tính', 'Oxy hoá', 'Kích ứng', 'Nguy hại sức khoẻ', 'Nguy hại môi trường', 'Khí nén', 'Dễ nổ', 'Không nguy hiểm'
            Fld StorageCondition 'Điều kiện bảo quản'       Choice  -Choices $StorageChoice
            Fld ParLevelQty     'Lượng tồn chuẩn'           Number  -Decimals 4 -Min 0 -Note 'Lượng muốn có khi kho đầy đủ (đơn vị gốc). Là mốc 100% để tính % còn lại. Để trống = hệ thống dùng PeakQty.'
            Fld LowStockPct     'Ngưỡng cảnh báo (%)'       Number  -Decimals 0 -Min 1 -Max 99 -Note 'Cảnh báo cần mua thêm khi tổng tồn nhỏ hơn % này của lượng tồn chuẩn. Để trống = dùng DefaultLowStockPct trong LabSettings.'
            Fld PeakQty         'Tồn cao nhất đã đạt'       Number  -Decimals 4 -Min 0 -Note 'Hệ thống tự cập nhật (LAB-F01) sau mỗi lần nhập = tổng tồn lớn nhất từng đạt. Dùng làm lượng chuẩn khi ParLevelQty trống; Admin có thể đặt lại.'
            Fld SDSLink         'Link SDS'                  Url
            Fld IsActive        'Đang sử dụng'              Boolean -Default '1'
        )
    }

    LabLocations = @{
        Description  = 'Vị trí lưu trữ (phòng / tủ / ngăn).'
        TitleDisplay = 'Tên vị trí'
        TitleIndexed = $true
        TitleUnique  = $true
        ViewFields   = @('LinkTitle', 'Room', 'IsActive')
        Fields       = @(
            Fld Room     'Phòng'         Text
            Fld Note     'Ghi chú'       Note
            Fld IsActive 'Đang sử dụng'  Boolean -Default '1'
        )
    }

    LabLots = @{
        Description  = 'Hoá chất đầu vào. Mỗi item = 1 chai/đơn vị vật lý, có 1 mã QR riêng. Chỉ flow được ghi.'
        TitleDisplay = 'Mã nội bộ'
        TitleIndexed = $true
        TitleUnique  = $true
        ViewFields   = @('LinkTitle', 'ChemName', 'MfgLot', 'ExpiryDate', 'RemainingQty', 'Unit', 'LocationName', 'Status')
        Fields       = @(
            Fld CatalogID     'ID danh mục'     Number -Decimals 0 -Indexed -Required -Note 'ID item trong LabCatalog.'
            Fld ChemName      'Tên hoá chất'    Text   -Indexed -Required -Note 'Snapshot tại thời điểm nhập, để tra cứu nhanh không cần join.'
            Fld CasNumber     'Số CAS'          Text   -Note 'Snapshot.'
            Fld MfgLot        'Số lô NSX'       Text   -Indexed
            Fld Manufacturer  'Hãng sản xuất'   Text
            Fld Supplier      'Nhà cung cấp'    Text
            Fld ReceivedDate  'Ngày nhận'       Date   -Indexed -Required
            Fld MfgDate       'Ngày sản xuất'   Date
            Fld ExpiryDate    'Hạn dùng'        Date   -Indexed
            Fld OpenedDate    'Ngày mở nắp'     Date   -Note 'Flow gán khi giao dịch xuất đầu tiên phát sinh (nếu để trống).'
            Fld InitialQty    'Lượng ban đầu'   Number -Decimals 4 -Min 0 -Required
            Fld RemainingQty  'Lượng còn lại'   Number -Decimals 4 -Min 0 -Note 'Cache. Luôn bằng tổng QtyDelta của LabLedger; chỉ flow LAB-C01 cập nhật.'
            Fld Unit          'Đơn vị'          Choice -Choices $UnitChoices -Required
            Fld LocationID    'ID vị trí'       Number -Decimals 0
            Fld LocationName  'Vị trí'          Text   -Note 'Snapshot tên vị trí.'
            Fld Status        'Trạng thái'      Choice -Choices $StatusLot -Default 'Available' -Indexed -Required
            Fld COALink       'Link COA'        Url
            Fld RegisteredBy  'Người đăng ký'   User   -Note 'Người gọi flow (lấy từ danh tính, không nhận từ client).'
            Fld Note          'Ghi chú'         Note
            Fld IsVoid        'Đã vô hiệu'      Boolean -Default '0'
            Fld VoidReason    'Lý do vô hiệu'   Note
        )
    }

    LabPreps = @{
        Description  = 'Hoá chất pha chế / dung dịch pha. Chỉ flow được ghi.'
        TitleDisplay = 'Mã hoá chất pha'
        TitleIndexed = $true
        TitleUnique  = $true
        ViewFields   = @('LinkTitle', 'PrepName', 'Concentration', 'PrepDate', 'ExpiryDate', 'RemainingQty', 'Unit', 'Status', 'ReviewStatus')
        Fields       = @(
            Fld PrepName        'Tên dung dịch'       Text    -Indexed -Required
            Fld PrepType        'Loại dung dịch'      Choice  -Choices 'Dung dịch gốc', 'Dung dịch làm việc', 'Dung dịch đệm', 'Thuốc thử', 'Pha loãng', 'Khác' -Default 'Dung dịch làm việc'
            Fld Concentration   'Nồng độ'             Text    -Note 'Văn bản tự do, ví dụ "0.1 mol/L", "1000 ppm".'
            Fld SOPRef          'SOP / phương pháp'   Text
            Fld Procedure       'Cách pha'            Note
            Fld PrepDate        'Ngày pha'            Date    -Indexed -Required
            Fld ExpiryDate      'Hạn dùng'            Date    -Indexed -Required -Note 'Không vượt hạn dùng sớm nhất của thành phần (cấu hình EnforcePrepExpiryLimit).'
            Fld FinalQty        'Lượng sau pha'       Number  -Decimals 4 -Min 0 -Required
            Fld RemainingQty    'Lượng còn lại'       Number  -Decimals 4 -Min 0 -Note 'Cache. Luôn bằng tổng QtyDelta của LabLedger.'
            Fld Unit            'Đơn vị'              Choice  -Choices $UnitChoices -Required
            Fld LocationID      'ID vị trí'           Number  -Decimals 0
            Fld LocationName    'Vị trí'              Text
            Fld StorageCondition 'Điều kiện bảo quản' Choice  -Choices $StorageChoice
            Fld Status          'Trạng thái'          Choice  -Choices $StatusPrep -Default 'Available' -Indexed -Required
            Fld ReviewStatus    'Trạng thái duyệt'    Choice  -Choices 'Pending', 'Approved', 'Rejected' -Default 'Pending'
            Fld ReviewedBy      'Người duyệt'         User    -Note 'Phải khác PreparedBy (nguyên tắc 4 mắt).'
            Fld ReviewedOn      'Ngày duyệt'          DateTime
            Fld PreparedBy      'Người pha'           User
            Fld Note            'Ghi chú'             Note
            Fld IsVoid          'Đã vô hiệu'          Boolean -Default '0'
            Fld VoidReason      'Lý do vô hiệu'       Note
        )
    }

    LabPrepItems = @{
        Description  = 'Thành phần của mỗi lần pha (công thức thực tế). Nguồn có thể là chai đầu vào hoặc một dung dịch pha khác.'
        TitleDisplay = 'Mã hoá chất pha'
        TitleIndexed = $true
        TitleUnique  = $false
        ViewFields   = @('LinkTitle', 'SourceType', 'SourceCode', 'SourceName', 'QtyUsed', 'Unit', 'ItemRole')
        Fields       = @(
            Fld PrepID       'ID dung dịch pha' Number -Decimals 0 -Indexed -Required
            Fld SourceType   'Loại nguồn'       Choice -Choices 'Lot', 'Prep' -Required
            Fld SourceID     'ID nguồn'         Number -Decimals 0 -Indexed -Required
            Fld SourceCode   'Mã nguồn'         Text   -Indexed -Required
            Fld SourceName   'Tên nguồn'        Text   -Note 'Snapshot.'
            Fld SourceMfgLot 'Số lô NSX nguồn'  Text   -Note 'Snapshot, chỉ có khi nguồn là Lot; phục vụ truy xuất nhanh.'
            Fld ItemRole     'Vai trò'          Choice -Choices 'Chất tan', 'Dung môi', 'Phụ gia' -Default 'Chất tan'
            Fld QtyUsed      'Lượng dùng'       Number -Decimals 4 -Min 0 -Required
            Fld Unit         'Đơn vị'           Choice -Choices $UnitChoices -Required
        )
    }

    LabLedger = @{
        Description  = 'Sổ cái xuất/nhập (append-only). Số dư của Lot/Prep = tổng QtyDelta. Nguồn sự thật cho lượng còn lại.'
        TitleDisplay = 'Mã đối tượng'
        TitleIndexed = $true
        TitleUnique  = $false
        ViewFields   = @('Created', 'LinkTitle', 'ItemType', 'TxnType', 'QtyDelta', 'Unit', 'BalanceAfter', 'RefCode', 'Actor')
        Fields       = @(
            Fld ItemType     'Loại đối tượng' Choice -Choices 'Lot', 'Prep' -Required
            Fld ItemID       'ID đối tượng'   Number -Decimals 0 -Indexed -Required
            Fld TxnType      'Loại giao dịch' Choice -Choices 'Receive', 'PrepCreate', 'PrepUse', 'TestUse', 'Adjust', 'Dispose', 'Reversal' -Required
            Fld QtyDelta     'Biến động'      Number -Decimals 4 -Required -Note 'Dương = nhập, âm = xuất.'
            Fld Unit         'Đơn vị'         Choice -Choices $UnitChoices -Required
            Fld BalanceAfter 'Số dư sau GD'   Number -Decimals 4
            Fld RefType      'Loại tham chiếu' Choice -Choices 'Prep', 'Report', 'Manual'
            Fld RefCode      'Mã tham chiếu'  Text   -Indexed -Note 'Mã dung dịch pha hoặc số biên bản liên quan.'
            Fld Reason       'Lý do'          Note   -Note 'Bắt buộc với Adjust / Dispose / Reversal.'
            Fld Actor        'Người thực hiện' User
        )
    }

    LabTestUsage = @{
        Description  = 'Liên kết biên bản thử nghiệm với hoá chất đã dùng (1 dòng = 1 biên bản x 1 hoá chất).'
        TitleDisplay = 'Số biên bản'
        TitleIndexed = $true
        TitleUnique  = $false
        ViewFields   = @('LinkTitle', 'TestName', 'ItemCode', 'ItemName', 'QtyUsed', 'Unit', 'UsedDate', 'Analyst')
        Fields       = @(
            Fld ReportUrl  'Link biên bản'   Url
            Fld TestName   'Phép thử / chỉ tiêu' Text
            Fld SampleCode 'Mã mẫu'          Text
            Fld ItemType   'Loại đối tượng'  Choice -Choices 'Lot', 'Prep' -Required
            Fld ItemID     'ID đối tượng'    Number -Decimals 0 -Indexed -Required
            Fld ItemCode   'Mã hoá chất'     Text   -Indexed -Required
            Fld ItemName   'Tên hoá chất'    Text   -Note 'Snapshot.'
            Fld QtyUsed    'Lượng dùng'      Number -Decimals 4 -Min 0 -Required
            Fld Unit       'Đơn vị'          Choice -Choices $UnitChoices -Required
            Fld UsedDate   'Ngày sử dụng'    DateTime -Indexed -Required
            Fld Analyst    'Người thử nghiệm' User
            Fld Note       'Ghi chú'         Note
        )
    }

    LabAudit = @{
        Description  = 'Nhật ký kiểm toán nghiệp vụ (append-only). Lưu thành công lẫn bị từ chối. Admin/Reviewer đọc.'
        TitleDisplay = 'Hành động'
        TitleIndexed = $true
        TitleUnique  = $false
        ViewFields   = @('Created', 'LinkTitle', 'EntityType', 'EntityCode', 'Result', 'Actor')
        Fields       = @(
            Fld EntityType 'Loại đối tượng' Choice -Choices 'Lot', 'Prep', 'Catalog', 'Report', 'System' -Required
            Fld EntityCode 'Mã đối tượng'   Text   -Indexed
            Fld Result     'Kết quả'        Choice -Choices 'Success', 'Rejected', 'Error' -Required
            Fld Detail     'Chi tiết'       Note   -Note 'JSON kết quả / lý do từ chối. Dùng để trả lại kết quả khi client gửi lại cùng RequestId.'
            Fld Actor      'Người thực hiện' User
            Fld RequestId  'Request Id'     Text   -Indexed -Note 'GUID do app sinh; chống ghi trùng khi bấm 2 lần / flow retry.'
            Fld RunId      'Flow run Id'    Text
        )
    }

    LabRoles = @{
        Description  = 'Phân quyền nghiệp vụ. Flow kiểm tra vai trò ở phía server; app chỉ dùng để ẩn/hiện chức năng.'
        TitleDisplay = 'Email (UPN, chữ thường)'
        TitleIndexed = $true
        TitleUnique  = $true
        ViewFields   = @('LinkTitle', 'DisplayName', 'Role', 'IsActive')
        Fields       = @(
            Fld DisplayName 'Họ tên'        Text
            Fld Role        'Vai trò'       Choice -Choices 'Admin', 'Analyst', 'Reviewer', 'Viewer' -Default 'Viewer' -Required
            Fld IsActive    'Đang hiệu lực' Boolean -Default '1'
        )
    }

    LabSettings = @{
        Description  = 'Cấu hình dạng khoá-giá trị. Chỉ Admin chỉnh sửa.'
        TitleDisplay = 'Khoá'
        TitleIndexed = $true
        TitleUnique  = $true
        ViewFields   = @('LinkTitle', 'Value', 'Description')
        Fields       = @(
            Fld Value       'Giá trị' Text
            Fld Description 'Mô tả'   Note
        )
    }
}

$LabSeedSettings = @(
    @{ Key = 'LabName';                 Value = 'Phòng thí nghiệm';  Desc = 'Tên hiển thị trên tiêu đề app và nhãn.' }
    @{ Key = 'ExpiryWarnDays';          Value = '30';                Desc = 'Cảnh báo hoá chất/dung dịch sắp hết hạn trong N ngày.' }
    @{ Key = 'DefaultLowStockPct';      Value = '20';                Desc = 'Ngưỡng cảnh báo sắp hết (%) mặc định, dùng cho hoá chất không tự đặt LowStockPct. Chai đang dùng dưới % này (so với lượng ban đầu) cũng được tô vàng.' }
    @{ Key = 'LabelBarcode';            Value = 'Code39';            Desc = 'Mã vạch tuyến tính in thêm trên nhãn để máy quét 1D (laser) đọc được: Code39 hoặc None. QR luôn được in.' }
    @{ Key = 'RequireIncomingRelease';  Value = 'false';             Desc = 'true: hoá chất mới nhập ở trạng thái Quarantine, Reviewer/Admin phải Release mới dùng được.' }
    @{ Key = 'EnforcePrepExpiryLimit';  Value = 'true';              Desc = 'true: hạn dùng dung dịch pha không được vượt hạn dùng sớm nhất của thành phần.' }
    @{ Key = 'MaxBottlesPerReceipt';    Value = '20';                Desc = 'Số chai tối đa tạo trong một lần đăng ký nhập.' }
    @{ Key = 'AlertEmails';             Value = '';                  Desc = 'Danh sách email nhận báo cáo hằng ngày (phân tách bằng dấu chấm phẩy).' }
    @{ Key = 'ReportUrlAllowedHosts';   Value = '';                  Desc = 'Hậu tố host được phép cho link biên bản/COA, phân tách bằng dấu chấm phẩy (vd .sharepoint.com). Trống = mọi https.' }
    @{ Key = 'QRMode';                  Value = 'CodeOnly';          Desc = 'CodeOnly: QR chứa mã nội bộ. DeepLink: QR chứa link mở thẳng app (cần AppLink).' }
    @{ Key = 'QRBaseUrl';               Value = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&margin=0&data='; Desc = 'PILOT ONLY. Dịch vụ tạo ảnh QR công cộng, chỉ nhận mã nội bộ. Thay bằng PCF/dịch vụ nội bộ trước khi go-live (xem docs/05).' }
    @{ Key = 'AppLink';                 Value = '';                  Desc = 'Link play của app, ví dụ https://apps.powerapps.com/play/<appId>?tenantId=<tid>. Dùng khi QRMode=DeepLink.' }
)
