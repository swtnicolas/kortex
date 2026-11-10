use std::io::Write;

pub struct Json {
    buf: Vec<u8>,
    comma: bool,
}

impl Json {
    pub fn new() -> Self {
        Json { buf: Vec::with_capacity(4096), comma: false }
    }

    pub fn reset(&mut self) {
        self.buf.clear();
        self.comma = false;
    }

    pub fn finish(&mut self) -> &[u8] {
        self.buf.push(0);
        &self.buf
    }

    fn separate(&mut self) {
        if self.comma {
            self.buf.push(b',');
        }
    }

    pub fn open(&mut self) -> &mut Self {
        self.separate();
        self.buf.push(b'{');
        self.comma = false;
        self
    }

    pub fn close(&mut self) -> &mut Self {
        self.buf.push(b'}');
        self.comma = true;
        self
    }

    pub fn open_list(&mut self) -> &mut Self {
        self.separate();
        self.buf.push(b'[');
        self.comma = false;
        self
    }

    pub fn close_list(&mut self) -> &mut Self {
        self.buf.push(b']');
        self.comma = true;
        self
    }

    pub fn key(&mut self, key: &str) -> &mut Self {
        self.separate();
        self.quote(key);
        self.buf.push(b':');
        self.comma = false;
        self
    }

    pub fn string(&mut self, value: &str) -> &mut Self {
        self.separate();
        self.quote(value);
        self.comma = true;
        self
    }

    pub fn number(&mut self, value: Option<f64>, decimals: usize) -> &mut Self {
        self.separate();
        match value {
            Some(v) if v.is_finite() => {
                let _ = write!(self.buf, "{v:.decimals$}");
            }
            _ => self.buf.extend_from_slice(b"null"),
        }
        self.comma = true;
        self
    }

    pub fn integer(&mut self, value: u64) -> &mut Self {
        self.separate();
        let _ = write!(self.buf, "{value}");
        self.comma = true;
        self
    }

    pub fn boolean(&mut self, value: bool) -> &mut Self {
        self.separate();
        self.buf.extend_from_slice(if value { b"true" } else { b"false" });
        self.comma = true;
        self
    }

    pub fn field(&mut self, key: &str, value: Option<f64>, decimals: usize) -> &mut Self {
        self.key(key).number(value, decimals)
    }

    fn quote(&mut self, text: &str) {
        self.buf.push(b'"');
        for c in text.chars() {
            match c {
                '"' => self.buf.extend_from_slice(b"\\\""),
                '\\' => self.buf.extend_from_slice(b"\\\\"),
                c if (c as u32) < 0x20 => {
                    let _ = write!(self.buf, "\\u{:04x}", c as u32);
                }
                c => {
                    let mut utf8 = [0; 4];
                    self.buf.extend_from_slice(c.encode_utf8(&mut utf8).as_bytes());
                }
            }
        }
        self.buf.push(b'"');
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(json: &mut Json) -> String {
        let bytes = json.finish();
        String::from_utf8(bytes[..bytes.len() - 1].to_vec()).unwrap()
    }

    #[test]
    fn separates_nested_values_with_single_commas() {
        let mut json = Json::new();
        json.open().field("a", Some(1.26), 1).key("b").open_list();
        json.open().field("c", None, 0).close();
        json.integer(7).close_list().key("d").boolean(true).close();
        assert_eq!(text(&mut json), r#"{"a":1.3,"b":[{"c":null},7],"d":true}"#);
    }

    #[test]
    fn escapes_quotes_backslashes_and_control_characters_in_process_names() {
        let mut json = Json::new();
        json.string("a\"b\\c\nd\u{1}é");
        assert_eq!(text(&mut json), "\"a\\\"b\\\\c\\u000ad\\u0001é\"");
    }

    #[test]
    fn writes_non_finite_numbers_as_null() {
        let mut json = Json::new();
        json.open_list().number(Some(f64::NAN), 1).number(Some(f64::INFINITY), 0).close_list();
        assert_eq!(text(&mut json), "[null,null]");
    }
}
