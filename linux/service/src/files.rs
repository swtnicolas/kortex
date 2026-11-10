use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::str::FromStr;

pub fn read(path: impl AsRef<Path>, buf: &mut Vec<u8>) -> bool {
    buf.clear();
    match File::open(path) {
        Ok(mut file) => file.read_to_end(buf).is_ok(),
        Err(_) => false,
    }
}

pub fn parse<T: FromStr>(bytes: &[u8]) -> Option<T> {
    std::str::from_utf8(bytes).ok()?.trim().parse().ok()
}

pub fn value<T: FromStr>(path: impl AsRef<Path>, buf: &mut Vec<u8>) -> Option<T> {
    if read(path, buf) { parse(buf) } else { None }
}

pub fn text(path: impl AsRef<Path>) -> Option<String> {
    std::fs::read_to_string(path).ok().map(|s| s.trim().to_owned())
}

pub fn fields(bytes: &[u8]) -> impl Iterator<Item = &[u8]> {
    bytes.split(|b| b.is_ascii_whitespace()).filter(|f| !f.is_empty())
}
