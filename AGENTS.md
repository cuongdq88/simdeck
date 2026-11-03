# STRICT PROJECT SCOPE &amp; SKILL ACCESS RULES

## 1. Project Isolation (Bắt buộc)

Chỉ được phép đọc, phân tích, tìm kiếm và chỉnh sửa mã nguồn nằm trong **thư mục dự án hiện tại (Current Project Root)**.

- Xác định Project Root từ workspace hiện đang mở.
- Chỉ truy cập các file, thư mục và tài nguyên thuộc Project Root.
- **TUYỆT ĐỐI KHÔNG** đọc, tìm kiếm, quét hoặc phân tích mã nguồn của các dự án khác.
- Không tự ý truy cập thư mục cha, thư mục ngang cấp hoặc workspace khác.
- Không thực hiện tìm kiếm trên toàn bộ máy tính, home directory hoặc các repository không thuộc dự án hiện tại.
- Không tự ý mở hoặc tham chiếu code của dự án khác, kể cả khi có quyền truy cập.

## 2. Skill Access Policy

Chỉ được đọc và sử dụng các skills thực sự liên quan đến nhiệm vụ hiện tại.

Nguồn skills được phép:

- Skills nằm trong Project Root.
- Skills được cung cấp chính thức bởi môi trường AI Agent, kể cả khi nằm ngoài Project Root, với điều kiện chỉ đọc đúng file hướng dẫn skill liên quan và các tài nguyên cần thiết của skill đó.

Quy định:

- Không quét toàn bộ thư mục skills khi không cần thiết.
- Không đọc những skills không liên quan.
- Không sử dụng skills làm lý do để truy cập mã nguồn của dự án khác.
- Ưu tiên sử dụng skills đã được cung cấp trong context trước khi đọc thêm file.

## 3. File Access &amp; Search Restrictions

- Giới hạn mọi thao tác `read`, `search`, `grep`, `glob`, `find`, `list` trong Project Root.
- Chỉ đọc những file cần thiết để hoàn thành nhiệm vụ.
- Không tự động đọc toàn bộ repository khi nhiệm vụ chỉ liên quan đến một module hoặc một số file.
- Không truy cập code thông qua symlink hoặc đường dẫn gián tiếp trỏ ra ngoài Project Root.
- Không sử dụng đường dẫn tuyệt đối bên ngoài Project Root để truy cập mã nguồn.
- Không tìm kiếm sang các project khác nhằm lấy ví dụ hoặc tái sử dụng code.

## 4. Context &amp; Token Optimization

- Ưu tiên đọc tài liệu dự án và những file liên quan trực tiếp.
- Tránh đọc file lớn, file sinh tự động, build outputs, dependencies và caches nếu không cần thiết.
- Không lặp lại việc đọc cùng một file nếu nội dung đã có trong context và còn phù hợp.
- Chỉ mở rộng phạm vi tìm kiếm khi có căn cứ rõ ràng về sự phụ thuộc trong cùng dự án.
- Không thu thập context không phục vụ nhiệm vụ.

## 5. Execution &amp; Modification Safety

- Chỉ chỉnh sửa file thuộc Project Root.
- Không chạy script hoặc command có tác dụng lên các project khác.
- Không tự ý cài đặt hoặc thay đổi cấu hình toàn cục.
- Không chỉnh sửa shared libraries, global configurations hoặc external repositories.
- Nếu cần truy cập tài nguyên ngoài phạm vi cho phép, phải giải thích lý do và yêu cầu người dùng chấp thuận trước.

## 6. Mandatory Behavior

Trước khi thực hiện nhiệm vụ:

1. Xác định Project Root.
2. Xác định các file/module liên quan trực tiếp.
3. Xác định skills cần thiết.
4. Chỉ đọc những tài nguyên đã xác định.
5. Thực hiện nhiệm vụ trong phạm vi được phép.

**HARD RULE:**

Never read, scan, search, inspect, or modify source code belonging to another project.

Never expand the project scope without explicit user authorization.

These restrictions apply to all tools, subagents, background tasks, shell commands, and delegated operations.