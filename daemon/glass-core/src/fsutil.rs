//! Ghi file an toàn: ghi vào file tạm cùng thư mục rồi đổi tên, để không
//! bao giờ có ai đọc phải file ghi dở.

use std::fs;
use std::io::{self, Write};
use std::path::Path;

pub fn write_atomic(path: &Path, content: &str) -> io::Result<()> {
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(dir)?;

    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("file");
    let tmp = dir.join(format!(".{name}.tmp-{}", std::process::id()));

    let result = (|| {
        let mut file = fs::File::create(&tmp)?;
        file.write_all(content.as_bytes())?;
        file.sync_all()?;
        fs::rename(&tmp, path)
    })();

    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

/// Chỉ ghi khi nội dung khác. Trả về `true` nếu file thay đổi.
pub fn write_if_changed(path: &Path, content: &str) -> io::Result<bool> {
    match fs::read_to_string(path) {
        Ok(existing) if existing == content => Ok(false),
        _ => write_atomic(path, content).map(|()| true),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_only_when_changed() {
        let dir = std::env::temp_dir().join(format!("glass-fsutil-{}", std::process::id()));
        let file = dir.join("sub/a.txt");
        assert!(write_if_changed(&file, "một").unwrap());
        assert!(!write_if_changed(&file, "một").unwrap());
        assert!(write_if_changed(&file, "hai").unwrap());
        assert_eq!(fs::read_to_string(&file).unwrap(), "hai");
        let leftovers: Vec<_> = fs::read_dir(file.parent().unwrap())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with('.'))
            .collect();
        assert!(leftovers.is_empty(), "còn file tạm: {leftovers:?}");
        fs::remove_dir_all(dir).unwrap();
    }
}
